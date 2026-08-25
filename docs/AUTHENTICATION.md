# Music Room Authentication System

This document describes the authentication system for the Music Room application, built according to the project specifications.

## Features

### 1. User Registration & Authentication
- **Email/Password Registration**: Users can create accounts using email and password
- **Social Authentication**: Support for Facebook and Google OAuth
- **Email Verification**: Mandatory email verification for email/password registrations
- **Password Reset**: Forgot password functionality with email-based reset

### 2. User Profile Management
The system supports three levels of information visibility:

#### Public Information (visible to all users)
- Email
- Display name
- Avatar
- Bio

#### Friends-Only Information
- Phone number
- Location
- All public information

#### Private Information (only visible to user themselves)
- Date of birth
- Music preferences (favorite genres, artists, music services)
- Subscription type and expiration
- All public and friends-only information

### 3. Social Features
- Friend request system
- Accept/reject/block friend requests
- View friends list
- View pending friend requests

### 4. Music Preferences
Users can set and update:
- Favorite music genres
- Favorite artists
- Linked music services (Spotify, Apple Music, etc.)

### 5. Subscription Management
- Free subscription (default)
- Premium subscription
- Pro subscription

## API Endpoints

### Authentication Endpoints

#### Register
```
POST /api/v1/auth/register/
Body:
{
  "email": "user@example.com",
  "password": "SecurePass123!",
  "password_confirm": "SecurePass123!",
  "display_name": "John Doe",
  "first_name": "John",
  "last_name": "Doe"
}

Response:
{
  "message": "User registered successfully. Please check your email to verify your account.",
  "user": {...},
  "tokens": {
    "access": "...",
    "refresh": "..."
  }
}
```

#### Login
```
POST /api/v1/auth/login/
Body:
{
  "email": "user@example.com",
  "password": "SecurePass123!"
}

Response:
{
  "message": "Login successful",
  "user": {...},
  "tokens": {
    "access": "...",
    "refresh": "..."
  }
}
```

#### Social Authentication
```
POST /api/v1/auth/social/
Body:
{
  "provider": "google",  // or "facebook"
  "access_token": "...",
  "email": "user@example.com",
  "social_id": "123456789",
  "display_name": "John Doe",
  "first_name": "John",
  "last_name": "Doe"
}

Response:
{
  "message": "Authentication successful",
  "user": {...},
  "tokens": {
    "access": "...",
    "refresh": "..."
  }
}
```

#### Link Social Account
```
POST /api/v1/auth/link-social/
Headers: Authorization: Bearer <access_token>
Body:
{
  "provider": "facebook",
  "social_id": "123456789",
  "access_token": "..."
}

Response:
{
  "message": "Facebook account linked successfully",
  "user": {...}
}
```

#### Verify Email
```
GET /api/v1/auth/verify-email/?token=<verification_token>

Response:
{
  "message": "Email verified successfully"
}
```

#### Request Password Reset
```
POST /api/v1/auth/password/reset/
Body:
{
  "email": "user@example.com"
}

Response:
{
  "message": "Password reset email sent"
}
```

#### Confirm Password Reset
```
POST /api/v1/auth/password/reset/confirm/
Body:
{
  "token": "...",
  "new_password": "NewSecurePass123!",
  "new_password_confirm": "NewSecurePass123!"
}

Response:
{
  "message": "Password reset successfully"
}
```

#### Change Password
```
POST /api/v1/auth/password/change/
Headers: Authorization: Bearer <access_token>
Body:
{
  "old_password": "OldPass123!",
  "new_password": "NewPass123!",
  "new_password_confirm": "NewPass123!"
}

Response:
{
  "message": "Password changed successfully"
}
```

#### Refresh Token
```
POST /api/v1/auth/token/refresh/
Body:
{
  "refresh": "..."
}

Response:
{
  "access": "..."
}
```

### Profile Endpoints

#### Get Own Profile
```
GET /api/v1/profile/
Headers: Authorization: Bearer <access_token>

Response:
{
  "id": 1,
  "email": "user@example.com",
  "display_name": "John Doe",
  "avatar": "...",
  "bio": "...",
  "first_name": "John",
  "last_name": "Doe",
  "phone_number": "...",
  "location": "...",
  "date_of_birth": "1990-01-01",
  "favorite_genres": [...],
  "favorite_artists": [...],
  "music_services": {...},
  "subscription_type": "free",
  "email_verified": true,
  ...
}
```

#### Update Profile
```
PATCH /api/v1/profile/
Headers: Authorization: Bearer <access_token>
Body:
{
  "display_name": "New Name",
  "bio": "Updated bio",
  "phone_number": "+1234567890",
  "location": "New York"
}

Response:
{
  "message": "Profile updated successfully",
  "user": {...}
}
```

#### Get Music Preferences
```
GET /api/v1/profile/music-preferences/
Headers: Authorization: Bearer <access_token>

Response:
{
  "favorite_genres": ["Rock", "Jazz", "Electronic"],
  "favorite_artists": ["Artist 1", "Artist 2"],
  "music_services": {
    "spotify": "user_id",
    "apple_music": "user_id"
  }
}
```

#### Update Music Preferences
```
PATCH /api/v1/profile/music-preferences/
Headers: Authorization: Bearer <access_token>
Body:
{
  "favorite_genres": ["Rock", "Jazz"],
  "favorite_artists": ["New Artist"],
  "music_services": {
    "spotify": "my_spotify_id"
  }
}

Response:
{
  "message": "Music preferences updated successfully",
  "preferences": {...}
}
```

#### Get Another User's Info
```
GET /api/v1/users/<user_id>/
Headers: Authorization: Bearer <access_token>

Response: (varies based on friendship status)
- If viewing self: Full profile
- If friends: Public + friends-only info
- If not friends: Public info only
```

### Friends Endpoints

#### Get Friends List
```
GET /api/v1/friends/
Headers: Authorization: Bearer <access_token>

Response: Array of friends with friends-only information
```

#### Get Friend Requests
```
GET /api/v1/friends/requests/
Headers: Authorization: Bearer <access_token>

Response:
{
  "received": [...],  // Friend requests you received
  "sent": [...]       // Friend requests you sent
}
```

#### Send Friend Request
```
POST /api/v1/friends/request/
Headers: Authorization: Bearer <access_token>
Body:
{
  "to_user_email": "friend@example.com"
}

Response:
{
  "message": "Friend request sent",
  "friendship": {...}
}
```

#### Respond to Friend Request
```
POST /api/v1/friends/request/<friendship_id>/respond/
Headers: Authorization: Bearer <access_token>
Body:
{
  "action": "accept"  // or "reject", "block"
}

Response:
{
  "message": "Friend request accepted",
  "friendship": {...}
}
```

## Models

### User Model
- Custom user model extending Django's AbstractUser
- Uses email as the primary identifier (no username)
- Supports email/password and social authentication
- Includes fields for all visibility levels
- Music preferences stored as JSON fields
- Subscription management

### Friendship Model
- Manages relationships between users
- Supports pending, accepted, rejected, and blocked statuses
- Prevents duplicate requests

### PasswordResetToken Model
- Manages password reset tokens
- Tokens expire after 24 hours
- One-time use only

## Security Features

1. **Password Validation**: Django's built-in password validators
2. **Email Verification**: Mandatory for email/password registrations
3. **JWT Authentication**: Secure token-based authentication
4. **Password Reset**: Secure token-based password reset
5. **Privacy Levels**: Different information visibility based on relationship
6. **CORS Configuration**: Configured for security
7. **Environment Variables**: Sensitive data stored in .env file

## Setup Instructions

1. **Install Dependencies**:
```bash
pip install -r requirements.txt
```

2. **Configure Environment Variables**:
Copy `.env.example` to `.env` and fill in your values:
```bash
cp .env.example .env
```

3. **Run Migrations**:
```bash
python manage.py makemigrations
python manage.py migrate
```

4. **Create Superuser**:
```bash
python manage.py createsuperuser
```

5. **Run Development Server**:
```bash
python manage.py runserver
```

## Social Authentication Setup

### Facebook
1. Create an app at https://developers.facebook.com
2. Get App ID and App Secret
3. Add them to `.env` file
4. Configure OAuth redirect URLs

### Google
1. Create a project at https://console.developers.google.com
2. Enable Google+ API
3. Create OAuth credentials
4. Add Client ID and Secret to `.env` file
5. Configure authorized redirect URIs

## Email Configuration

For email verification and password reset to work, configure your email settings:

### Gmail Example:
1. Enable 2-factor authentication
2. Generate an app password
3. Add to `.env`:
```
EMAIL_HOST=smtp.gmail.com
EMAIL_HOST_USER=your-email@gmail.com
EMAIL_HOST_PASSWORD=your-app-password
```

## Testing the API

You can use tools like Postman, curl, or any HTTP client to test the endpoints.

Example with curl:
```bash
# Register
curl -X POST http://localhost:8000/api/v1/auth/register/ \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "TestPass123!",
    "password_confirm": "TestPass123!",
    "display_name": "Test User"
  }'

# Login
curl -X POST http://localhost:8000/api/v1/auth/login/ \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "TestPass123!"
  }'

# Get Profile (use access token from login)
curl -X GET http://localhost:8000/api/v1/profile/ \
  -H "Authorization: Bearer <your_access_token>"
```

## Next Steps

After setting up authentication, you can proceed with implementing:
1. Music Track Vote service
2. Music Playlist Editor service
3. Music Control Delegation service

All these services will use the authentication system we've built to manage user access and permissions.
