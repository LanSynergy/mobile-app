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

    parts = [f"{icon} <b>Aetherfin Build</b>"]
    parts.append("\u2500" * 30)
    parts.append(f"<b>Branch:</b> <code>{branch}</code>")
    if mode:
        parts.append(f"<b>Mode:</b> <code>{mode}</code>")
    parts.append(f"<b>Build ID:</b> <code>{build_id}</code>")
    parts.append(f"<b>Triggered by:</b> <code>{actor}</code>")
    parts.append("\u2500" * 30)

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
    """Delete init message, then send one final failure message."""
    _delete_message(os.environ.get('TG_MESSAGE_ID'))

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

    _send_text(text, reply_markup)


def send_text():
    """Delete init message, then send a simple text result (APK too large or not found)."""
    _delete_message(os.environ.get('TG_MESSAGE_ID'))

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

    _send_text(text, reply_markup)


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
    else:
        print(f"Unknown action: {action}")
        sys.exit(1)


if __name__ == '__main__':
    main()
