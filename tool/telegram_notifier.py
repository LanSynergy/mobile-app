import os
import sys
import json
import uuid
from urllib.request import Request, urlopen
from urllib.error import HTTPError

# Read environment variables set by GitHub Actions
BOT_TOKEN = os.environ.get('TG_BOT_TOKEN')
CHAT_ID = os.environ.get('TG_CHAT_ID')

if not BOT_TOKEN or not CHAT_ID:
    print("Error: TG_BOT_TOKEN and TG_CHAT_ID environment variables must be set.")
    sys.exit(1)


def send_request(url, data=None, headers=None):
    if headers is None:
        headers = {}
    req = Request(url, data=data, headers=headers)
    try:
        with urlopen(req) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except HTTPError as e:
        print(f"HTTP Error {e.code}: {e.read().decode('utf-8')}")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


def get_header(icon="\U0001f528"):
    """Build the message header with build context."""
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
        parts.append("\u2500" * 30)
        parts.append(f"<b>Last Commit:</b>")
        parts.append(f"<code>{sha}</code> \u2014 {commit}")
    parts.append(f"<b>Triggered by:</b> <code>{actor}</code>")
    parts.append("\u2500" * 30)
    if timestamp:
        parts.append(f"<i>{timestamp}</i>")

    return "\n".join(parts)


def build_message(status_text, icon="\U0001f528"):
    """Combine header + status block."""
    header = get_header(icon)
    if status_text:
        return f"{header}\n<blockquote>{status_text}</blockquote>"
    return header


def _delete_message(msg_id):
    """Delete a message by ID. Silently ignores failures."""
    if not msg_id:
        return
    try:
        url = f"https://api.telegram.org/bot{BOT_TOKEN}/deleteMessage"
        payload = json.dumps({
            "chat_id": CHAT_ID,
            "message_id": int(msg_id)
        }).encode('utf-8')
        headers = {"Content-Type": "application/json"}
        req = Request(url, data=payload, headers=headers)
        urlopen(req)
        print(f"Deleted init message {msg_id}.")
    except Exception as e:
        print(f"Failed to delete init message {msg_id}: {e}")


def _send_text(text, reply_markup=None):
    """Send a new text message. Returns the message ID."""
    payload = {
        "chat_id": CHAT_ID,
        "text": text,
        "parse_mode": "HTML",
        "disable_web_page_preview": True
    }
    if reply_markup:
        payload["reply_markup"] = reply_markup

    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    data = json.dumps(payload).encode('utf-8')
    headers = {"Content-Type": "application/json"}

    result = send_request(url, data=data, headers=headers)
    if result.get('ok'):
        new_id = result['result']['message_id']
        print(f"Sent final message {new_id}.")
        return new_id
    else:
        print(f"Failed to send message: {result}")
        sys.exit(1)


def init_message():
    """Send the 'starting' message. Saves message ID to GITHUB_ENV."""
    text = build_message("\u23f3 Setting up build environment...")
    msg_id = _send_text(text)
    print(f"TG_MESSAGE_ID={msg_id}")
    github_env = os.environ.get('GITHUB_ENV')
    if github_env:
        with open(github_env, 'a') as f:
            f.write(f"TG_MESSAGE_ID={msg_id}\n")


def send_apk():
    """Delete init message, then send APK document as the final success message."""
    file_path = os.environ.get('TG_APK_PATH')
    filename = os.environ.get('TG_APK_NAME')

    if not file_path or not filename:
        print("Error: TG_APK_PATH and TG_APK_NAME must be set.")
        sys.exit(1)

    # Delete the 'starting' message first
    _delete_message(os.environ.get('TG_MESSAGE_ID'))

    caption_lines = [
        "\u2705 <b>Aetherfin Build Successful!</b>",
        "\u2500" * 30,
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
        "\u2500" * 30,
        "<i>{timestamp}</i>",
    ]

    caption = "\n".join(caption_lines).format(
        mode=os.environ.get('TG_MODE', ''),
        name=filename,
        size=os.environ.get('TG_SIZE', ''),
        build_id=os.environ.get('TG_BUILD_ID', ''),
        sha=os.environ.get('TG_SHA', ''),
        branch=os.environ.get('TG_BRANCH', ''),
        commit=os.environ.get('TG_COMMIT', ''),
        timestamp=os.environ.get('TG_TIMESTAMP', ''),
        actor=os.environ.get('TG_ACTOR', ''),
    )

    with open(file_path, 'rb') as f:
        file_data = f.read()

    # Build inline keyboard buttons
    reply_markup = {
        "inline_keyboard": [
            [
                {"text": "\U0001f528 View Run", "url": os.environ.get('TG_RUN_URL', '')},
                {"text": "\U0001f4bb View Commit", "url": os.environ.get('TG_COMMIT_URL', '')}
            ]
        ]
    }
    reply_markup_json = json.dumps(reply_markup)

    # Build multipart form-data manually (stdlib only)
    boundary = uuid.uuid4().hex
    body = b''
    body += f'--{boundary}\r\nContent-Disposition: form-data; name="chat_id"\r\n\r\n{CHAT_ID}\r\n'.encode()
    body += f'--{boundary}\r\nContent-Disposition: form-data; name="caption"\r\n\r\n{caption}\r\n'.encode()
    body += f'--{boundary}\r\nContent-Disposition: form-data; name="parse_mode"\r\n\r\nHTML\r\n'.encode()
    body += f'--{boundary}\r\nContent-Disposition: form-data; name="reply_markup"\r\n\r\n{reply_markup_json}\r\n'.encode()
    body += (
        f'--{boundary}\r\n'
        f'Content-Disposition: form-data; name="document"; filename="{filename}"\r\n'
        f'Content-Type: application/vnd.android.package-archive\r\n\r\n'
    ).encode() + file_data + b'\r\n'
    body += f'--{boundary}--\r\n'.encode()

    url = f'https://api.telegram.org/bot{BOT_TOKEN}/sendDocument'
    headers = {'Content-Type': f'multipart/form-data; boundary={boundary}'}

    result = send_request(url, data=body, headers=headers)
    if result.get('ok'):
        print("Sent APK document successfully.")
    else:
        print(f"Failed to send APK: {result}")
        sys.exit(1)


def fail_message():
    """Edit the init message to show build failure, or send a new one."""
    msg_id = os.environ.get('TG_MESSAGE_ID')

    branch = os.environ.get('TG_BRANCH', 'unknown')
    build_id = os.environ.get('TG_BUILD_ID', 'unknown')
    actor = os.environ.get('TG_ACTOR', 'unknown')
    run_url = os.environ.get('TG_RUN_URL', '')

    text = (
        "\u274c <b>Aetherfin Build Failed!</b>\n"
        "\u2500" * 30 + "\n"
        f"<b>Branch:</b> <code>{branch}</code>\n"
        f"<b>Build ID:</b> <code>{build_id}</code>\n"
        f"<b>Triggered by:</b> <code>{actor}</code>\n"
        "\u2500" * 30 + "\n"
        "<blockquote>Build failed during compilation or testing.</blockquote>"
    )

    reply_markup = {}
    if run_url:
        reply_markup = {
            "inline_keyboard": [[
                {"text": "\U0001f6a7 View Error Log", "url": run_url}
            ]]
        }

    if msg_id:
        payload = {
            "chat_id": CHAT_ID,
            "message_id": int(msg_id),
            "text": text,
            "parse_mode": "HTML",
            "disable_web_page_preview": True,
        }
        if reply_markup:
            payload["reply_markup"] = reply_markup

        url = f"https://api.telegram.org/bot{BOT_TOKEN}/editMessageText"
        data = json.dumps(payload).encode('utf-8')
        headers = {"Content-Type": "application/json"}
        try:
            send_request(url, data=data, headers=headers)
            print(f"Edited message {msg_id} to show build failure.")
            return
        except Exception as e:
            print(f"Warning: Failed to edit message: {e}")

    _send_text(text, reply_markup)


def send_text():
    """Edit the init message to show success (APK too large or not found), or send a new one."""
    msg_id = os.environ.get('TG_MESSAGE_ID')

    text = (
        "\u2705 <b>Aetherfin Build Successful!</b>\n"
        "\u2500" * 30 + "\n"
        "<blockquote>Build completed, but the APK exceeds Telegram's 50 MB limit "
        "or was not found. Download from CI artifacts instead.</blockquote>\n"
        "\u2500" * 30 + "\n"
        "<i>{timestamp}</i>"
    ).format(
        timestamp=os.environ.get('TG_TIMESTAMP', ''),
    )

    reply_markup = {}
    run_url = os.environ.get('TG_RUN_URL', '')
    if run_url:
        reply_markup = {
            "inline_keyboard": [[
                {"text": "\U0001f528 Download from CI", "url": run_url}
            ]]
        }

    if msg_id:
        payload = {
            "chat_id": CHAT_ID,
            "message_id": int(msg_id),
            "text": text,
            "parse_mode": "HTML",
            "disable_web_page_preview": True,
        }
        if reply_markup:
            payload["reply_markup"] = reply_markup

        url = f"https://api.telegram.org/bot{BOT_TOKEN}/editMessageText"
        data = json.dumps(payload).encode('utf-8')
        headers = {"Content-Type": "application/json"}
        try:
            send_request(url, data=data, headers=headers)
            print(f"Edited message {msg_id} to show success without APK.")
            return
        except Exception as e:
            print(f"Warning: Failed to edit message: {e}")

    _send_text(text, reply_markup)


def update_message():
    """Edit the existing init message with updated progress status."""
    msg_id = os.environ.get('TG_MESSAGE_ID')
    status_text = os.environ.get('TG_STATUS_TEXT', '')

    if not msg_id:
        print("Warning: TG_MESSAGE_ID not set — skipping progress update.")
        return

    icon = os.environ.get('TG_ICON', '\U0001f528')
    text = build_message(status_text, icon=icon)

    payload = {
        "chat_id": CHAT_ID,
        "message_id": int(msg_id),
        "text": text,
        "parse_mode": "HTML",
        "disable_web_page_preview": True,
    }

    url = f"https://api.telegram.org/bot{BOT_TOKEN}/editMessageText"
    data = json.dumps(payload).encode('utf-8')
    headers = {"Content-Type": "application/json"}

    try:
        result = send_request(url, data=data, headers=headers)
        if result.get('ok'):
            print(f"Updated message {msg_id} to: {status_text}")
        else:
            print(f"Warning: Failed to update message: {result}")
    except Exception as e:
        print(f"Warning: Telegram editMessageText failed: {e}")


def release_success():
    """Edit the init message with release success tag info, or send a new one."""
    msg_id = os.environ.get('TG_MESSAGE_ID')

    tag = os.environ.get('TG_TAG', '')
    run_url = os.environ.get('TG_RUN_URL', '')
    release_url = os.environ.get('TG_RELEASE_URL', '')
    branch = os.environ.get('TG_BRANCH', '')
    actor = os.environ.get('TG_ACTOR', '')
    timestamp = os.environ.get('TG_TIMESTAMP', '')

    text = (
        "\U0001f680 <b>Aetherfin Release Successful!</b>\n"
        "\u2500" * 30 + "\n"
        f"<b>Tag:</b> <code>{tag}</code>\n"
        f"<b>Branch:</b> <code>{branch}</code>\n"
        f"<b>Triggered by:</b> <code>{actor}</code>\n"
        "\u2500" * 30 + "\n"
        "\U00002705 Release published successfully!\n"
        "\u2500" * 30 + "\n"
        f"<i>{timestamp}</i>"
    )

    buttons = []
    if run_url:
        buttons.append({"text": "\U0001f528 View Run", "url": run_url})
    if release_url:
        buttons.append({"text": "\U0001f4e6 Release", "url": release_url})

    reply_markup = {}
    if buttons:
        reply_markup = {"inline_keyboard": [buttons]}

    if msg_id:
        payload = {
            "chat_id": CHAT_ID,
            "message_id": int(msg_id),
            "text": text,
            "parse_mode": "HTML",
            "disable_web_page_preview": True,
        }
        if reply_markup:
            payload["reply_markup"] = reply_markup

        url = f"https://api.telegram.org/bot{BOT_TOKEN}/editMessageText"
        data = json.dumps(payload).encode('utf-8')
        headers = {"Content-Type": "application/json"}
        try:
            send_request(url, data=data, headers=headers)
            print(f"Edited message {msg_id} to show release success.")
            return
        except Exception as e:
            print(f"Warning: Failed to edit message: {e}")

    _send_text(text, reply_markup)


def release_fail():
    """Edit the init message to show release failure, or send a new one."""
    msg_id = os.environ.get('TG_MESSAGE_ID')

    branch = os.environ.get('TG_BRANCH', 'unknown')
    tag = os.environ.get('TG_TAG', 'unknown')
    actor = os.environ.get('TG_ACTOR', 'unknown')
    run_url = os.environ.get('TG_RUN_URL', '')

    text = (
        "\u274c <b>Aetherfin Release Failed!</b>\n"
        "\u2500" * 30 + "\n"
        f"<b>Tag:</b> <code>{tag}</code>\n"
        f"<b>Branch:</b> <code>{branch}</code>\n"
        f"<b>Triggered by:</b> <code>{actor}</code>\n"
        "\u2500" * 30 + "\n"
        "<blockquote>Release failed during the workflow.</blockquote>"
    )

    reply_markup = {}
    if run_url:
        reply_markup = {
            "inline_keyboard": [[
                {"text": "\U0001f6a7 View Error Log", "url": run_url}
            ]]
        }

    if msg_id:
        payload = {
            "chat_id": CHAT_ID,
            "message_id": int(msg_id),
            "text": text,
            "parse_mode": "HTML",
            "disable_web_page_preview": True,
        }
        if reply_markup:
            payload["reply_markup"] = reply_markup

        url = f"https://api.telegram.org/bot{BOT_TOKEN}/editMessageText"
        data = json.dumps(payload).encode('utf-8')
        headers = {"Content-Type": "application/json"}
        try:
            send_request(url, data=data, headers=headers)
            print(f"Edited message {msg_id} to show release failure.")
            return
        except Exception as e:
            print(f"Warning: Failed to edit message: {e}")

    _send_text(text, reply_markup)


def progress_watch():
    """Live-progress watcher for long build steps.

    Runs as a background process (&) alongside the build command.
    Periodically edits the Telegram message to show elapsed time
    and a growing progress bar. Killed via SIGTERM when the build
    finishes. The bar cycles — 20 segments × 45 s = ~15 min per
    full lap.
    """
    import signal
    import time

    def _handle_sigterm(signum, frame):
        sys.exit(0)

    signal.signal(signal.SIGTERM, _handle_sigterm)

    msg_id = os.environ.get('TG_MESSAGE_ID')
    if not msg_id:
        print("Error: TG_MESSAGE_ID not set — progress_watch skipped.")
        sys.exit(1)

    icon = os.environ.get('TG_ICON', '\U0001f528')
    status_text = os.environ.get('TG_STATUS_TEXT', 'Building...')
    start = time.time()
    bar_len = 20
    interval = 10  # seconds between updates
    tick = 0

    while True:
        elapsed_s = int(time.time() - start)
        mins = elapsed_s // 60
        secs = elapsed_s % 60
        elapsed_str = f"{mins}m {secs:02d}s" if mins > 0 else f"{secs}s"

        # Cyclic bar: fills over bar_len ticks (~15 min at 45 s)
        pos = (tick % bar_len) + 1
        bar = '\u2588' * pos + '\u2591' * (bar_len - pos)

        progress_line = f"<code>[{bar}]</code> {elapsed_str} elapsed"

        header = get_header(icon)
        text = f"{header}\n<blockquote>{status_text}\n{progress_line}</blockquote>"

        payload = {
            "chat_id": CHAT_ID,
            "message_id": int(msg_id),
            "text": text,
            "parse_mode": "HTML",
            "disable_web_page_preview": True,
        }
        url = f"https://api.telegram.org/bot{BOT_TOKEN}/editMessageText"
        data = json.dumps(payload).encode('utf-8')
        headers = {"Content-Type": "application/json"}

        try:
            req = Request(url, data=data, headers=headers)
            urlopen(req)
        except Exception:
            pass  # may be killed mid-request — don't pollute logs

        tick += 1
        time.sleep(interval)


def main():
    if len(sys.argv) < 2:
        print("Usage: python tool/telegram_notifier.py <init|send_apk|send_text|fail>")
        sys.exit(1)

    action = sys.argv[1]
    if action == 'init':
        init_message()
    elif action == 'send_apk':
        send_apk()
    elif action == 'send_text':
        send_text()
    elif action == 'fail':
        fail_message()
    elif action == 'update':
        update_message()
    elif action == 'release_success':
        release_success()
    elif action == 'release_fail':
        release_fail()
    elif action == 'progress_watch':
        progress_watch()
    else:
        print(f"Unknown action: {action}")
        sys.exit(1)


if __name__ == '__main__':
    main()
