# Security Policy

## Reporting a vulnerability

Do not open a public issue for suspected vulnerabilities, leaked credentials, or
certificate material. Use GitHub's private vulnerability reporting for this
repository when available. If that channel is unavailable, contact the
repository owner privately through the contact method shown on their GitHub
profile.

Include the affected version or commit, reproduction steps, impact, and any
suggested mitigation. Never include a live API key, private key, certificate
archive, or production domain data in a report.

## Secret handling

The project never requires an API key in a command-line argument, Git-tracked
file, issue, CI log, or pull request. Revoke and replace any key that may have
been exposed.
