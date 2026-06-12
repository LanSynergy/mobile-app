# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| Latest  | :white_check_mark: |
| < Latest | :x:               |

Only the latest release receives security updates. Always update to the most recent version.

## Reporting a Vulnerability

**Please do NOT report security vulnerabilities through public GitHub issues.**

If you discover a security vulnerability in Aetherfin, please report it responsibly:

### Email

Send a report to **mirzaspc@gmail.com** with:

1. **Description** of the vulnerability
2. **Steps to reproduce** the issue
3. **Potential impact** assessment
4. **Suggested fix** (if any)

### What to include

- The component affected (e.g., audio engine, auth flow, lyrics parser)
- Android version and device information
- Aetherfin version
- Any relevant logs (`adb logcat | grep aetherfin`)

### Response timeline

| Action | Timeline |
|--------|----------|
| Acknowledgment | Within 48 hours |
| Initial assessment | Within 1 week |
| Fix or mitigation | Depends on severity |

### What to expect

- We will acknowledge receipt of your report within 48 hours
- We will provide an initial assessment within 1 week
- We will work with you to understand and validate the issue
- We will develop and test a fix before public disclosure
- We will credit reporters in the release notes (unless anonymity is requested)

## Security Considerations

### Authentication

- Aetherfin stores server credentials in `flutter_secure_storage` (encrypted at rest)
- Subsonic API uses per-request MD5 token authentication (fresh salt each request)
- Jellyfin uses header-based authentication (tokens never appear in URLs)

### Network

- All connections use HTTPS when available
- Stream URLs embed auth as query parameters (required by FFmpeg/libmpv)
- No telemetry, analytics, or phone-home behavior

### Local Data

- Audio settings are stored in `SharedPreferences` (plaintext, non-sensitive)
- Database (Drift/SQLite) contains only music metadata — no credentials
- Cover art is cached to disk with LRU eviction

### Dependencies

- Dependencies are audited via Dependabot (configured in `.github/dependabot.yml`)
- Run `flutter pub outdated` to check for updates

## Scope

The following are **in scope** for security reports:

- Authentication bypass or credential leakage
- Remote code execution
- Man-in-the-middle attacks on server communication
- Data exfiltration via the app
- Denial of service via malformed input (LRC files, metadata, server responses)
- Privilege escalation on the device

The following are **out of scope**:

- Issues in the Jellyfin or Navidrome server software
- Physical device security
- Social engineering attacks
- Issues requiring a rooted device to exploit

## Disclosure Policy

We follow coordinated disclosure:

1. Reporter submits vulnerability privately
2. We acknowledge and investigate
3. We develop a fix
4. We release the fix
5. We publish a security advisory
6. We credit the reporter (unless they prefer anonymity)

We request a 90-day disclosure window. If a fix is not ready within 90 days, we will coordinate a public disclosure date with the reporter.
