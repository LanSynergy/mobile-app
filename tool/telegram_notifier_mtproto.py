"""
telegram_notifier_mtproto.py — MTProto-based Telegram notifier.

Uses Telethon to bypass the 50MB Bot API limit (supports up to 2GB).
Text messages still use Bot API for simplicity.

Required env vars:
  TG_API_ID          — Telegram API ID (from my.telegram.org)
  TG_API_HASH        — Telegram API hash (from my.telegram.org)
  TG_SESSION_BASE64  — Base64-encoded .session file
  TG_CHAT_ID         — Target chat/channel ID
  TG_BOT_TOKEN       — Bot token (for text messages)
"""

import os
import sys
import json
import base64
import tempfile
import asyncio
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError


def _require_env(name):
    val = os.environ.get(name)
    if not val:
        print(f"Error: {name} environment variable must be set.")
        sys.exit(1)
    return val


def _bot_request(url, data=None, headers=None, timeout=30):
    bot_token = os.environ.get('TG_BOT_TOKEN')
    if not bot_token:
        return None
    if headers is None:
        headers = {}
    req = Request(url, data=data, headers=headers)
    try:
        with urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except HTTPError as e:
        print(f"HTTP Error {e.code}: {e.read().decode('utf-8')}")
        return None
    except Exception as e:
        print(f"Error: {e}")
        return None


def _get_header(icon="\U0001f528"):
    branch = os.environ.get('TG_BRANCH', 'unknown')
    build_id = os.environ.get('TG_BUILD_ID', 'unknown')
    mode = os.environ.get('TG_MODE', '')
    actor = os.environ.get('TG_ACTOR', 'unknown')
    tag = os.environ.get('TG_TAG', '')
    sha = os.environ.get('TG_SHA', '')
    commit = os.environ.get('TG_COMMIT', '')
    timestamp = os.environ.get('TG_TIMESTAMP', '')

    parts = [f"{icon} <b>Aetherfin {'Release' if tag else 'Build'}</b>"]
    if tag:
        parts.append(f"<b>Tag:</b> <code>{tag}</code>")
    parts.append(f"<b>Branch:</b> <code>{branch}</code>")
    if mode:
        parts.append(f"<b>Mode:</b> <code>{mode}</code>")
    parts.append(f"<b>Build ID:</b> <code>{build_id}</code>")
    if sha and commit:
        parts.append("\u2500" * 12)
        parts.append("<b>Last Commit:</b>")
        parts.append(f"<code>{sha}</code> \u2014 {commit}")
    parts.append(f"<b>Triggered by:</b> <code>{actor}</code>")
    parts.append("\u2500" * 12)
    if timestamp:
        parts.append(f"<i>{timestamp}</i>")
    return "\n".join(parts)


def _build_message(status_text, icon="\U0001f528"):
    header = _get_header(icon)
    if status_text:
        return f"{header}\n<blockquote>{status_text}</blockquote>"
    return header


def _send_text(text, reply_markup=None):
    bot_token = os.environ.get('TG_BOT_TOKEN')
    chat_id = os.environ.get('TG_CHAT_ID')
    if not bot_token or not chat_id:
        print("Warning: TG_BOT_TOKEN or TG_CHAT_ID not set.")
        return None

    payload = {
        "chat_id": chat_id,
        "text": text,
        "parse_mode": "HTML",
        "disable_web_page_preview": True
    }
    if reply_markup:
        payload["reply_markup"] = reply_markup

    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    data = json.dumps(payload).encode('utf-8')
    headers = {"Content-Type": "application/json"}

    result = _bot_request(url, data=data, headers=headers)
    if result and result.get('ok'):
        new_id = result['result']['message_id']
        print(f"Sent message {new_id}.")
        return new_id
    print(f"Failed to send message: {result}")
    return None


def _edit_text(msg_id, text, reply_markup=None):
    bot_token = os.environ.get('TG_BOT_TOKEN')
    chat_id = os.environ.get('TG_CHAT_ID')
    if not bot_token or not chat_id or not msg_id:
        return False

    payload = {
        "chat_id": chat_id,
        "message_id": int(msg_id),
        "text": text,
        "parse_mode": "HTML",
        "disable_web_page_preview": True,
    }
    if reply_markup:
        payload["reply_markup"] = reply_markup

    url = f"https://api.telegram.org/bot{bot_token}/editMessageText"
    data = json.dumps(payload).encode('utf-8')
    headers = {"Content-Type": "application/json"}

    result = _bot_request(url, data=data, headers=headers)
    return bool(result and result.get('ok'))


def _delete_message(msg_id):
    if not msg_id:
        return
    bot_token = os.environ.get('TG_BOT_TOKEN')
    chat_id = os.environ.get('TG_CHAT_ID')
    if not bot_token or not chat_id:
        return
    try:
        url = f"https://api.telegram.org/bot{bot_token}/deleteMessage"
        payload = json.dumps({"chat_id": chat_id, "message_id": int(msg_id)}).encode('utf-8')
        headers = {"Content-Type": "application/json"}
        req = Request(url, data=payload, headers=headers)
        urlopen(req, timeout=10)
        print(f"Deleted message {msg_id}.")
    except Exception as e:
        print(f"Failed to delete message {msg_id}: {e}")


# ---------------------------------------------------------------------------
# MTProto
# ---------------------------------------------------------------------------

def _get_mtproto_client():
    from telethon import TelegramClient

    api_id = int(_require_env('TG_API_ID'))
    api_hash = _require_env('TG_API_HASH')
    session_b64 = _require_env('TG_SESSION_BASE64')

    session_data = base64.b64decode(session_b64)
    session_dir = tempfile.mkdtemp()
    session_path = Path(session_dir) / 'aetherfin.session'
    session_path.write_bytes(session_data)

    client = TelegramClient(
        str(session_path.with_suffix('')),
        api_id,
        api_hash
    )
    return client, session_dir


async def _send_file_mtproto(file_path, caption, reply_markup=None):
    from telethon.tl.types import DocumentAttributeFilename, KeyboardButtonUrl
    from telethon.errors import (
        SessionPasswordNeededError, AuthKeyError,
        FloodWaitError, PhoneCodeInvalidError
    )

    chat_id = int(_require_env('TG_CHAT_ID'))
    client, session_dir = _get_mtproto_client()

    try:
        # Connect first (just TCP, no auth)
        await asyncio.wait_for(client.connect(), timeout=30)

        # Check if we have a valid session without triggering auth flow
        if not await client.is_user_authorized():
            print("Error: MTProto session is not authorized.")
            print("The session may have been revoked. Regenerate TG_SESSION_BASE64.")
            await client.disconnect()
            sys.exit(1)

        buttons = None
        if reply_markup and 'inline_keyboard' in reply_markup:
            buttons = []
            for row in reply_markup['inline_keyboard']:
                row_buttons = []
                for btn in row:
                    if 'url' in btn:
                        row_buttons.append(KeyboardButtonUrl(btn['text'], btn['url']))
                if row_buttons:
                    buttons.append(row_buttons)

        filename = os.path.basename(file_path)
        file_size = os.path.getsize(file_path)
        size_mb = file_size / (1024 * 1024)
        print(f"Uploading {filename} ({size_mb:.1f} MB) via MTProto...")

        # Upload with progress timeout (5 min for large files)
        await asyncio.wait_for(
            client.send_file(
                chat_id,
                file_path,
                caption=caption,
                parse_mode='html',
                force_document=True,
                attributes=[DocumentAttributeFilename(file_name=filename)],
                buttons=buttons
            ),
            timeout=300
        )

        print(f"Sent {filename} successfully via MTProto.")

    except asyncio.TimeoutError:
        print("MTProto upload timed out. Check network or regenerate session.")
        sys.exit(1)
    except (AuthKeyError, SessionPasswordNeededError, PhoneCodeInvalidError) as e:
        print(f"Error: MTProto session is invalid: {e}")
        print("Regenerate TG_SESSION_BASE64 and update the secret.")
        sys.exit(1)
    except FloodWaitError as e:
        print(f"Error: Telegram rate limit. Wait {e.seconds} seconds.")
        sys.exit(1)
    except Exception as e:
        print(f"MTProto upload failed: {e}")
        sys.exit(1)
    finally:
        try:
            await client.disconnect()
        except Exception:
            pass
        import shutil
        shutil.rmtree(session_dir, ignore_errors=True)


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

def init_message():
    text = _build_message("\u23f3 Setting up build environment...")
    msg_id = _send_text(text)
    if msg_id:
        print(f"TG_MESSAGE_ID={msg_id}")
        github_env = os.environ.get('GITHUB_ENV')
        if github_env:
            with open(github_env, 'a') as f:
                f.write(f"TG_MESSAGE_ID={msg_id}\n")


def send_apk():
    file_path = os.environ.get('TG_APK_PATH')
    filename = os.environ.get('TG_APK_NAME')

    if not file_path or not filename:
        print("Error: TG_APK_PATH and TG_APK_NAME must be set.")
        sys.exit(1)

    if not os.path.exists(file_path):
        print(f"Error: File not found: {file_path}")
        sys.exit(1)

    _delete_message(os.environ.get('TG_MESSAGE_ID'))

    caption_lines = [
        "\u2705 <b>Aetherfin Build Successful!</b>",
        "\u2500" * 12,
        "<b>App:</b> <code>{name}</code>",
        "<b>Mode:</b> <code>{mode}</code>",
        "<b>Size:</b> <code>{size}</code>",
        "",
        "<b>Branch:</b> <code>{branch}</code>",
        "<b>Build ID:</b> <code>{build_id}</code>",
        "<b>Triggered by:</b> <code>{actor}</code>",
        "",
        "<b>Last Commit:</b>",
        "<code>{sha}</code> \u2014 {commit}",
        "\u2500" * 12,
        "<i>{timestamp}</i>",
    ]

    caption = "\n".join(caption_lines).format(
        name=filename,
        mode=os.environ.get('TG_MODE', ''),
        size=os.environ.get('TG_SIZE', ''),
        build_id=os.environ.get('TG_BUILD_ID', ''),
        sha=os.environ.get('TG_SHA', ''),
        branch=os.environ.get('TG_BRANCH', ''),
        commit=os.environ.get('TG_COMMIT', ''),
        timestamp=os.environ.get('TG_TIMESTAMP', ''),
        actor=os.environ.get('TG_ACTOR', ''),
    )

    reply_markup = {
        "inline_keyboard": [
            [
                {"text": "\U0001f528 View Run", "url": os.environ.get('TG_RUN_URL', '')},
                {"text": "\U0001f4bb View Commit", "url": os.environ.get('TG_COMMIT_URL', '')}
            ]
        ]
    }

    asyncio.run(_send_file_mtproto(file_path, caption, reply_markup))


def send_text():
    msg_id = os.environ.get('TG_MESSAGE_ID')
    text = (
        "\u2705 <b>Aetherfin Build Successful!</b>\n"
        "\u2500" * 12 + "\n"
        "<blockquote>Build completed successfully.</blockquote>\n"
        "\u2500" * 12 + "\n"
        "<i>{timestamp}</i>"
    ).format(timestamp=os.environ.get('TG_TIMESTAMP', ''))

    reply_markup = {}
    run_url = os.environ.get('TG_RUN_URL', '')
    if run_url:
        reply_markup = {"inline_keyboard": [[{"text": "\U0001f528 Download from CI", "url": run_url}]]}

    if msg_id and _edit_text(msg_id, text, reply_markup):
        print(f"Edited message {msg_id} to show success.")
        return
    _send_text(text, reply_markup)


def fail_message():
    msg_id = os.environ.get('TG_MESSAGE_ID')
    text = (
        "\u274c <b>Aetherfin Build Failed!</b>\n"
        "\u2500" * 12 + "\n"
        f"<b>Branch:</b> <code>{os.environ.get('TG_BRANCH', 'unknown')}</code>\n"
        f"<b>Build ID:</b> <code>{os.environ.get('TG_BUILD_ID', 'unknown')}</code>\n"
        f"<b>Triggered by:</b> <code>{os.environ.get('TG_ACTOR', 'unknown')}</code>\n"
        "\u2500" * 12 + "\n"
        "<blockquote>Build failed during compilation or testing.</blockquote>"
    )

    reply_markup = {}
    run_url = os.environ.get('TG_RUN_URL', '')
    if run_url:
        reply_markup = {"inline_keyboard": [[{"text": "\U0001f6a7 View Error Log", "url": run_url}]]}

    if msg_id and _edit_text(msg_id, text, reply_markup):
        print(f"Edited message {msg_id} to show build failure.")
        return
    _send_text(text, reply_markup)


def update_message():
    msg_id = os.environ.get('TG_MESSAGE_ID')
    status_text = os.environ.get('TG_STATUS_TEXT', '')
    if not msg_id:
        print("Warning: TG_MESSAGE_ID not set -- skipping progress update.")
        return
    icon = os.environ.get('TG_ICON', '\U0001f528')
    text = _build_message(status_text, icon=icon)
    if _edit_text(msg_id, text):
        print(f"Updated message {msg_id} to: {status_text}")
    else:
        print(f"Warning: Failed to update message {msg_id}.")


def progress_watch():
    import signal
    import time

    def _handle_sigterm(signum, frame):
        sys.exit(0)

    signal.signal(signal.SIGTERM, _handle_sigterm)

    msg_id = os.environ.get('TG_MESSAGE_ID')
    if not msg_id:
        print("Error: TG_MESSAGE_ID not set -- progress_watch skipped.")
        sys.exit(1)

    icon = os.environ.get('TG_ICON', '\U0001f528')
    status_text = os.environ.get('TG_STATUS_TEXT', 'Building...')
    start = time.time()
    bar_len = 20
    interval = 2
    tick = 0

    while True:
        elapsed_s = int(time.time() - start)
        mins = elapsed_s // 60
        secs = elapsed_s % 60
        elapsed_str = f"{mins}m {secs:02d}s" if mins > 0 else f"{secs}s"

        pos = (tick % bar_len) + 1
        bar = '\u2588' * pos + '\u2591' * (bar_len - pos)
        progress_line = f"<code>[{bar}]</code> {elapsed_str} elapsed"
        header = _get_header(icon)
        text = f"{header}\n<blockquote>{status_text}\n{progress_line}</blockquote>"
        _edit_text(msg_id, text)
        tick += 1
        time.sleep(interval)


def release_success():
    msg_id = os.environ.get('TG_MESSAGE_ID')
    tag = os.environ.get('TG_TAG', '')
    run_url = os.environ.get('TG_RUN_URL', '')
    release_url = os.environ.get('TG_RELEASE_URL', '')
    branch = os.environ.get('TG_BRANCH', '')
    actor = os.environ.get('TG_ACTOR', '')
    timestamp = os.environ.get('TG_TIMESTAMP', '')

    text = (
        "\U0001f680 <b>Aetherfin Release Successful!</b>\n"
        "\u2500" * 12 + "\n"
        f"<b>Tag:</b> <code>{tag}</code>\n"
        f"<b>Branch:</b> <code>{branch}</code>\n"
        f"<b>Triggered by:</b> <code>{actor}</code>\n"
        "\u2500" * 12 + "\n"
        "\U00002705 Release published successfully!\n"
        "\u2500" * 12 + "\n"
        f"<i>{timestamp}</i>"
    )

    buttons = []
    if run_url:
        buttons.append({"text": "\U0001f528 View Run", "url": run_url})
    if release_url:
        buttons.append({"text": "\U0001f4e6 Release", "url": release_url})
    reply_markup = {"inline_keyboard": [buttons]} if buttons else {}

    if msg_id and _edit_text(msg_id, text, reply_markup):
        print(f"Edited message {msg_id} to show release success.")
        return
    _send_text(text, reply_markup)


def release_fail():
    msg_id = os.environ.get('TG_MESSAGE_ID')
    tag = os.environ.get('TG_TAG', 'unknown')
    actor = os.environ.get('TG_ACTOR', 'unknown')
    run_url = os.environ.get('TG_RUN_URL', '')

    text = (
        "\u274c <b>Aetherfin Release Failed!</b>\n"
        "\u2500" * 12 + "\n"
        f"<b>Tag:</b> <code>{tag}</code>\n"
        f"<b>Triggered by:</b> <code>{actor}</code>\n"
        "\u2500" * 12 + "\n"
        "<blockquote>Release failed during the workflow.</blockquote>"
    )

    reply_markup = {}
    if run_url:
        reply_markup = {"inline_keyboard": [[{"text": "\U0001f6a7 View Error Log", "url": run_url}]]}

    if msg_id and _edit_text(msg_id, text, reply_markup):
        print(f"Edited message {msg_id} to show release failure.")
        return
    _send_text(text, reply_markup)


def main():
    if len(sys.argv) < 2:
        print("Usage: python tool/telegram_notifier_mtproto.py <action>")
        print("Actions: init, send_apk, send_text, fail, update, release_success, release_fail, progress_watch")
        sys.exit(1)

    action = sys.argv[1]
    actions = {
        'init': init_message,
        'send_apk': send_apk,
        'send_text': send_text,
        'fail': fail_message,
        'update': update_message,
        'release_success': release_success,
        'release_fail': release_fail,
        'progress_watch': progress_watch,
    }

    if action in actions:
        actions[action]()
    else:
        print(f"Unknown action: {action}")
        sys.exit(1)


if __name__ == '__main__':
    main()
