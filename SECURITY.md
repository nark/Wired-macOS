# Security Policy

## Supported Versions

Only the latest released version of Wired Client receives security fixes.

| Version | Supported |
|---------|-----------|
| 3.0.x beta | ✅ |
| < 3.0 | ❌ |

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Please use [GitHub Private Vulnerability Reporting](https://github.com/nark/Wired-macOS/security/advisories/new) to report security issues confidentially.

### What to include

- A clear description of the issue
- Steps to reproduce
- Affected versions or commit range
- Estimated impact
- Any proof of concept, logs, screenshots, or crash details that help validate the report

### What to expect

| Step | Timeline |
|------|----------|
| Acknowledgement | Within 72 hours |
| Triage and severity assessment | Within 7 days |
| Patch and coordinated disclosure | Within 90 days |

If you would like to remain uncredited in release notes or advisories, say so in the report.

## Attack Surface

Important security-sensitive areas in this repository include:

- **Connection and authentication flows** in the macOS client (including the cross-version protocol diff exchange — see [`WiredSwift/COMPATIBILITY.md`](../WiredSwift/COMPATIBILITY.md))
- **Server identity trust** and TOFU fingerprint handling
- **Credential storage** in the macOS Keychain
- **File transfers** and local file handling
- **`wiredsyncd`** background synchronization and local IPC
- **Administration views** that expose privileged server operations

Because this is a client application, reports involving credential leakage, trust bypass, unsafe file access, sync daemon privilege issues, or unintended execution paths are especially valuable.

## Out of Scope

The following are generally not considered security vulnerabilities for this project:

- Issues in third-party dependencies that should be reported upstream first
- Attacks requiring local admin or physical access to the machine
- Reports that only affect unsupported or outdated releases
- Purely theoretical concerns without a credible exploitation path
- UI bugs without a security impact
