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

def get_base_caption(status_text):
    branch = os.environ.get('TG_BRANCH', 'unknown')
    build_id = os.environ.get('TG_BUILD_ID', 'unknown')
    actor = os.environ.get('TG_ACTOR', 'unknown')
    
    return (
        f"⏳ <b>Aetherfin Build Progress</b>\n"
        f"──────────────────────────────\n"
        f"🌿 <b>Branch:</b> <code>{branch}</code>\n"
        f"🔢 <b>Build ID:</b> <code>{build_id}</code>\n"
        f"👤 <b>Triggered by:</b> <code>{actor}</code>\n"
        f"──────────────────────────────\n"
        f"{status_text}"
    )

def init_message():
    text = get_base_caption("🔄 <i>Setting up build environment...</i>")
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    payload = json.dumps({
        "chat_id": CHAT_ID,
        "text": text,
        "parse_mode": "HTML",
        "disable_web_page_preview": True
    }).encode('utf-8')
    headers = {"Content-Type": "application/json"}
    
    result = send_request(url, data=payload, headers=headers)
    if result.get('ok'):
        msg_id = result['result']['message_id']
        print(f"TG_MESSAGE_ID={msg_id}")
        github_env = os.environ.get('GITHUB_ENV')
        if github_env:
            with open(github_env, 'a') as f:
                f.write(f"TG_MESSAGE_ID={msg_id}\n")
    else:
        print(f"Telegram error: {result}")
        sys.exit(1)

def update_message(status_text):
    msg_id = os.environ.get('TG_MESSAGE_ID')
    if not msg_id:
        print("Warning: TG_MESSAGE_ID not set, skipping update.")
        return
        
    text = get_base_caption(status_text)
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/editMessageText"
    payload = json.dumps({
        "chat_id": CHAT_ID,
        "message_id": int(msg_id),
        "text": text,
        "parse_mode": "HTML",
        "disable_web_page_preview": True
    }).encode('utf-8')
    headers = {"Content-Type": "application/json"}
    send_request(url, data=payload, headers=headers)
    print(f"Updated status to: {status_text}")

def fail_message():
    msg_id = os.environ.get('TG_MESSAGE_ID')
    if not msg_id:
        print("Warning: TG_MESSAGE_ID not set, skipping fail notification.")
        return
        
    branch = os.environ.get('TG_BRANCH', 'unknown')
    build_id = os.environ.get('TG_BUILD_ID', 'unknown')
    actor = os.environ.get('TG_ACTOR', 'unknown')
    run_url = os.environ.get('TG_RUN_URL', '')
    
    text = (
        f"❌ <b>Aetherfin Build Failed!</b>\n"
        f"──────────────────────────────\n"
        f"🌿 <b>Branch:</b> <code>{branch}</code>\n"
        f"🔢 <b>Build ID:</b> <code>{build_id}</code>\n"
        f"👤 <b>Triggered by:</b> <code>{actor}</code>\n"
        f"──────────────────────────────\n"
        f"💥 <i>Build failed during compilation or testing.</i>"
    )
    
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/editMessageText"
    
    reply_markup = {}
    if run_url:
        reply_markup = {
            "inline_keyboard": [[
                {"text": "🛠️ View Error Log", "url": run_url}
            ]]
        }
        
    payload = json.dumps({
        "chat_id": CHAT_ID,
        "message_id": int(msg_id),
        "text": text,
        "parse_mode": "HTML",
        "reply_markup": reply_markup,
        "disable_web_page_preview": True
    }).encode('utf-8')
    headers = {"Content-Type": "application/json"}
    send_request(url, data=payload, headers=headers)
    print("Sent failure notification.")

def send_apk():
    file_path = os.environ.get('TG_APK_PATH')
    filename = os.environ.get('TG_APK_NAME')
    
    if not file_path or not filename:
        print("Error: TG_APK_PATH and TG_APK_NAME must be set.")
        sys.exit(1)
        
    caption = (
        '🚀 <b>Aetherfin Build Successful!</b>\n'
        '──────────────────────────────\n'
        '📱 <b>App:</b> <code>{name}</code>\n'
        '⚙️ <b>Mode:</b> <code>{mode}</code>\n'
        '💾 <b>Size:</b> <code>{size}</code>\n\n'
        '🌿 <b>Branch:</b> <code>{branch}</code>\n'
        '🔢 <b>Build ID:</b> <code>{build_id}</code>\n'
        '👤 <b>Triggered by:</b> <code>{actor}</code>\n\n'
        '💬 <b>Last Commit:</b>\n'
        '<code>{sha}</code> — <i>{commit}</i>\n'
        '──────────────────────────────\n'
        '📅 <i>{timestamp}</i>'
    ).format(
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
                {"text": "🛠️ View Run", "url": os.environ.get('TG_RUN_URL', '')},
                {"text": "💻 View Commit", "url": os.environ.get('TG_COMMIT_URL', '')}
            ]
        ]
    }
    reply_markup_json = json.dumps(reply_markup)

    # Build multipart form-data manually (stdlib only)
    boundary = uuid.uuid4().hex
    body = b''

    # chat_id field
    body += f'--{boundary}\r\nContent-Disposition: form-data; name="chat_id"\r\n\r\n{CHAT_ID}\r\n'.encode()
    # caption field
    body += f'--{boundary}\r\nContent-Disposition: form-data; name="caption"\r\n\r\n{caption}\r\n'.encode()
    # parse_mode
    body += f'--{boundary}\r\nContent-Disposition: form-data; name="parse_mode"\r\n\r\nHTML\r\n'.encode()
    # reply_markup
    body += f'--{boundary}\r\nContent-Disposition: form-data; name="reply_markup"\r\n\r\n{reply_markup_json}\r\n'.encode()
    # document file
    body += (
        f'--{boundary}\r\n'
        f'Content-Disposition: form-data; name="document"; filename="{filename}"\r\n'
        f'Content-Type: application/vnd.android.package-archive\r\n\r\n'
    ).encode() + file_data + b'\r\n'
    # closing boundary
    body += f'--{boundary}--\r\n'.encode()

    url = f'https://api.telegram.org/bot{BOT_TOKEN}/sendDocument'
    headers = {'Content-Type': f'multipart/form-data; boundary={boundary}'}
    
    result = send_request(url, data=body, headers=headers)
    if result.get('ok'):
        print(f"Sent APK document successfully.")
        
        # Now delete the progress message to clean up the chat
        msg_id = os.environ.get('TG_MESSAGE_ID')
        if msg_id:
            delete_url = f"https://api.telegram.org/bot{BOT_TOKEN}/deleteMessage"
            delete_payload = json.dumps({
                "chat_id": CHAT_ID,
                "message_id": int(msg_id)
            }).encode('utf-8')
            delete_headers = {"Content-Type": "application/json"}
            try:
                send_request(delete_url, data=delete_payload, headers=delete_headers)
                print(f"Deleted progress message {msg_id}.")
            except Exception as e:
                print(f"Failed to delete progress message: {e}")
    else:
        print(f"Failed to send APK: {result}")
        sys.exit(1)

def main():
    if len(sys.argv) < 2:
        print("Usage: python tool/telegram_notifier.py <init|update|fail|send_apk> [status_text]")
        sys.exit(1)
        
    action = sys.argv[1]
    if action == 'init':
        init_message()
    elif action == 'update':
        status_text = sys.argv[2] if len(sys.argv) > 2 else "<i>Working...</i>"
        update_message(status_text)
    elif action == 'fail':
        fail_message()
    elif action == 'send_apk':
        send_apk()
    else:
        print(f"Unknown action: {action}")
        sys.exit(1)

if __name__ == '__main__':
    main()
