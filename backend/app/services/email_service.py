"""
Transactional email delivery.

Sends via SMTP when configured (any provider: Gmail, Mailgun, Postmark, SES
SMTP interface, etc.), otherwise logs the message so flows like password reset
and email verification stay fully testable in dev.

Configure via environment variables:
    SMTP_HOST       e.g. smtp.sendgrid.net          (required to actually send)
    SMTP_PORT       default 587
    SMTP_USERNAME   SMTP auth user
    SMTP_PASSWORD   SMTP auth password / API key
    SMTP_FROM       From address, e.g. "Mytr.AI <no-reply@mytr.ai>"
    SMTP_USE_TLS    "true" (STARTTLS, default) or "false"

Delivery uses the stdlib `smtplib` (no extra dependency) run in a worker thread
so it never blocks the async event loop.
"""

import asyncio
import logging
import os
import smtplib
from email.message import EmailMessage

logger = logging.getLogger("mytr.email")

# Deep link the mobile app registers (see AndroidManifest / Info.plist). The
# reset/verify screens parse the `token` query parameter from these URLs.
PASSWORD_RESET_URL_TEMPLATE = os.getenv(
    "PASSWORD_RESET_URL_TEMPLATE",
    "mytrai://reset-password?token={token}",
)
EMAIL_VERIFY_URL_TEMPLATE = os.getenv(
    "EMAIL_VERIFY_URL_TEMPLATE",
    "mytrai://verify-email?token={token}",
)


def _smtp_configured() -> bool:
    return bool(os.getenv("SMTP_HOST"))


def _send_via_smtp(to: str, subject: str, body: str) -> None:
    host = os.getenv("SMTP_HOST")
    port = int(os.getenv("SMTP_PORT", "587"))
    username = os.getenv("SMTP_USERNAME")
    password = os.getenv("SMTP_PASSWORD")
    sender = os.getenv("SMTP_FROM", "Mytr.AI <no-reply@mytr.ai>")
    use_tls = os.getenv("SMTP_USE_TLS", "true").lower() != "false"

    message = EmailMessage()
    message["From"] = sender
    message["To"] = to
    message["Subject"] = subject
    message.set_content(body)

    with smtplib.SMTP(host, port, timeout=15) as server:
        if use_tls:
            server.starttls()
        if username and password:
            server.login(username, password)
        server.send_message(message)


async def _send(to: str, subject: str, body: str) -> None:
    """Deliver an email via SMTP, or log it when SMTP isn't configured."""
    if not _smtp_configured():
        logger.warning(
            "[email_service] SMTP not configured — email not sent.\n"
            "  To: %s\n  Subject: %s\n  Body:\n%s",
            to, subject, body,
        )
        return
    try:
        await asyncio.to_thread(_send_via_smtp, to, subject, body)
        logger.info("[email_service] Sent '%s' to %s", subject, to)
    except Exception:
        logger.exception("[email_service] Failed to send '%s' to %s", subject, to)
        raise


async def send_password_reset_email(email: str, reset_token: str) -> None:
    reset_link = PASSWORD_RESET_URL_TEMPLATE.format(token=reset_token)
    body = (
        "We received a request to reset your Mytr.AI password.\n\n"
        "Tap the link below to choose a new password. This link expires in 30 minutes:\n\n"
        f"{reset_link}\n\n"
        "If you didn't request this, you can safely ignore this email."
    )
    await _send(to=email, subject="Reset your Mytr.AI password", body=body)


async def send_verification_email(email: str, verify_token: str) -> None:
    verify_link = EMAIL_VERIFY_URL_TEMPLATE.format(token=verify_token)
    body = (
        "Welcome to Mytr.AI! Please confirm your email address.\n\n"
        "Tap the link below to verify. This link expires in 24 hours:\n\n"
        f"{verify_link}\n\n"
        "If you didn't create a Mytr.AI account, you can ignore this email."
    )
    await _send(to=email, subject="Verify your Mytr.AI email", body=body)


async def send_account_locked_email(email: str) -> None:
    body = (
        "We detected several failed sign-in attempts on your Mytr.AI account, so "
        "we've temporarily locked it for your protection.\n\n"
        "It will unlock automatically in 15 minutes. If this wasn't you, please "
        "reset your password immediately — resetting your password also unlocks "
        "the account."
    )
    await _send(to=email, subject="Your Mytr.AI account was temporarily locked", body=body)
