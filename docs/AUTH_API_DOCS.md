# Music Room — Auth API Documentation

Base URL (local dev): `http://localhost:8000/api/v1/auth/`

All requests/responses are JSON. Endpoints that require authentication expect:
```
Authorization: Bearer <access_token>
```

**Dev mode:** while `EMAIL_DEV_MODE=1` (default in local dev), no real emails are sent. Instead, the verification/reset link, `uid`, and `token` are returned directly in the API response under `dev_verification` or `dev_reset`, so you can test the full flow without needing a working mailbox. This will be turned off (`EMAIL_DEV_MODE=0`) before the real defense/demo.

---

## 1. Register (email/password)

**`POST /register/`**

| Field | Type | Required |
|---|---|---|
| email | string | yes |
| password | string (min 8 chars) | yes |
| first_name | string | no |
| last_name | string | no |

**Success — `201 Created`**
```json
{
  "user": {
    "id": 1,
    "email": "khadija@test.com",
    "first_name": "Khadija",
    "last_name": "Mahdi",
    "registration_method": "email",
    "is_email_verified": false,
    "date_joined": "2026-08-09T10:00:00Z"
  },
  "detail": "Registration successful. Please check your email to verify your account before logging in.",
  "dev_verification": {
    "link": "musicroom://app/verify-email?uid=MQ&token=abc123...",
    "uid": "MQ",
    "token": "abc123..."
  }
}
```
*(`dev_verification` only appears while `EMAIL_DEV_MODE=1`.)*

**Important:** No login tokens are returned at register time. The account is created but **cannot log in** until the email is verified.

**Errors — `400 Bad Request`**
- Email already registered
- Password too short / too weak
- Missing required fields

---

## 2. Verify Email

In production, the verification email contains a deep link with `uid` and `token`:
```
musicroom://app/verify-email?uid=MQ&token=abc123...
```
The app catches this link, extracts `uid`/`token`, and calls:

**`POST /verify-email/`**

| Field | Type | Required |
|---|---|---|
| uid | string | yes |
| token | string | yes |

**Success — `200 OK`**
```json
{ "detail": "Email verified successfully." }
```

**Errors — `400 Bad Request`**
- Invalid/malformed `uid`
- Invalid or expired `token`
- Token already used — **tokens are single-use**, replaying a consumed link fails

After success, `is_email_verified` becomes `true` and the user can log in.

---

## 3. Resend Verification Email

For a user who registered but never got (or lost) the verification email. **Unauthenticated** — takes only the email address.

**`POST /resend-verification/`**

| Field | Type | Required |
|---|---|---|
| email | string | yes |

**Success — `200 OK`** *(always returned, regardless of whether the email exists — security measure, avoids leaking which emails are registered)*
```json
{
  "detail": "If an account with that email exists and is unverified, a verification email has been sent.",
  "dev_verification": { "link": "...", "uid": "...", "token": "..." }
}
```
*(`dev_verification` only appears if the account is real, unverified, and `EMAIL_DEV_MODE=1`.)*

If the account doesn't exist, or is already verified, the response is identical **except `dev_verification` is simply absent** — no error is raised either way.

---

## 4. Login

**`POST /login/`**

| Field | Type | Required |
|---|---|---|
| email | string | yes |
| password | string | yes |

**Success — `200 OK`**
```json
{
  "user": { "id": 1, "email": "khadija@test.com", "...": "..." },
  "tokens": {
    "access": "eyJhbGciOi...",
    "refresh": "eyJhbGciOi..."
  }
}
```

**Errors — `400 Bad Request`**

| Situation | Response |
|---|---|
| Wrong password | `{"detail": "Invalid email or password."}` |
| Email doesn't exist | `{"detail": "Invalid email or password."}` *(identical to wrong password — prevents account enumeration)* |
| Account disabled | `{"detail": "This account is disabled."}` |
| **Email not verified** | `{"detail": "Email not verified. Please verify your email before logging in.", "code": "email_not_verified"}` |

**Mobile app note:** check `"code": "email_not_verified"` specifically to trigger a "Resend verification email" screen, rather than string-matching the message text.

**Note:** this check only applies to `registration_method == "email"` accounts. Google-registered users skip it entirely (Google already confirms their email — see the upcoming Google Sign-In doc).

---

## 5. Get Current User

**`GET /me/`** *(requires auth)*

**Success — `200 OK`**
```json
{
  "id": 1,
  "email": "khadija@test.com",
  "first_name": "Khadija",
  "last_name": "Mahdi",
  "registration_method": "email",
  "is_email_verified": true,
  "date_joined": "2026-08-09T10:00:00Z"
}
```

**Errors**
- `401 Unauthorized` — missing/invalid/expired token

---

## 6. Refresh Access Token

Access tokens expire after 1 day, refresh tokens after 20 days. When the access token expires, use the refresh token to get a new one instead of forcing a full re-login.

**`POST /token/refresh/`**

| Field | Type | Required |
|---|---|---|
| refresh | string | yes |

**Success — `200 OK`**
```json
{ "access": "eyJhbGciOi..." }
```

**Errors — `401 Unauthorized`**
- Refresh token expired or invalid → send the user to the login screen

**Mobile app note:** store both tokens securely (Keychain on iOS, Keystore/EncryptedSharedPreferences on Android — never plain storage). On any `401` from any API call, try `/token/refresh/` once before giving up.

---

## 7. Request Password Reset

For email/password users who forgot their password. **Does not apply to Google users** — they have no password on our side.

**`POST /password-reset/`**

| Field | Type | Required |
|---|---|---|
| email | string | yes |

**Success — `200 OK`** *(always, regardless of whether the email exists)*
```json
{
  "detail": "If an account with that email exists, a reset link has been sent.",
  "dev_reset": { "link": "...", "uid": "...", "token": "..." }
}
```
*(`dev_reset` only appears if the account is real and `EMAIL_DEV_MODE=1`.)*

---

## 8. Confirm Password Reset

**`POST /password-reset/confirm/`**

| Field | Type | Required |
|---|---|---|
| uid | string | yes |
| token | string | yes |
| new_password | string | yes |

**Success — `200 OK`**
```json
{ "detail": "Password reset successful." }
```

**Errors — `400 Bad Request`**
- Invalid/expired token
- Password fails validators (too short, too common, all-numeric, too similar to email)

After this, the user logs in immediately with the new password (verification status is unaffected either way).

---

## Full flow diagrams

### Email/password signup
```
App:      POST /register/  {email, password, first_name, last_name}
Backend:  201, no tokens, "check your email"
          (dev mode: link/uid/token included directly in response)

User taps link in email → app opens musicroom://app/verify-email?uid=..&token=..
App:      POST /verify-email/ {uid, token}
Backend:  200, is_email_verified = true

App:      POST /login/ {email, password}
Backend:  200, {user, tokens: {access, refresh}}
App:      stores tokens securely
```

### Making authenticated requests
```
App:      GET /me/   Header: Authorization: Bearer <access>
Backend:  200 if valid
          401 if expired
              → App: POST /token/refresh/ {refresh} → new access → retry original request
              → 401 on refresh too → send user to login screen
```

### Forgot password
```
App:      POST /password-reset/ {email}
Backend:  200 always (regardless of whether email exists)

User taps link in email → app opens musicroom://app/reset-password?uid=..&token=..
App:      POST /password-reset/confirm/ {uid, token, new_password}
Backend:  200, password changed

App:      POST /login/ {email, new_password} → tokens
```

### Resend verification (if the first email never arrived)
```
App:      POST /resend-verification/ {email}
Backend:  200 always (regardless of whether email exists or is already verified)
          (dev mode: link/uid/token included if account is real and unverified)
```

---

## Status codes cheat sheet

| Code | Meaning here |
|---|---|
| 200 | OK (login, verify, resend, reset, me, refresh) |
| 201 | Created (register) |
| 400 | Validation error — bad input, wrong credentials, invalid/expired token |
| 401 | Not authenticated — missing/invalid/expired access token |

---

## Security patterns used throughout

- **No account enumeration**: login, resend-verification, and password-reset-request all return identical responses whether or not the target email exists.
- **Single-use tokens**: verification and reset tokens become invalid once used — no replay.
- **No tokens issued until verified**: register never returns login tokens; login blocks unverified email/password accounts outright.
- **Google accounts bypass email verification** (handled by Google) but never get a password on our side — password reset is filtered to `registration_method='email'` only.

---

## Deep link scheme

All email links currently use:
```
musicroom://app
```
Confirm with the team whether this stays as the final scheme name for the app, or whether a hosted web fallback page is also needed for testers without the app installed. This is a one-line change in `FRONTEND_BASE_URL` (`user/views.py`) once decided.

---

## Not yet built (coming next)

- **Google Sign-In** — `POST /auth/google/`, verifies a Google ID token from the app, finds-or-creates the user + links a `SocialAccount`, and issues the same JWT tokens as `/login/`. Will follow this same doc format once built.
- **Rate limiting** on login, register, resend, and password-reset — required by the subject's security section, not yet implemented.
- **Action logging** (platform, device, app version) on auth actions — required by the subject, not yet implemented.
