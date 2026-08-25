# authentication/views.py

from django.conf import settings

from rest_framework import generics, status, serializers
from rest_framework.response import Response
from rest_framework.permissions import AllowAny, IsAuthenticated

from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.exceptions import TokenError

from drf_spectacular.utils import extend_schema, extend_schema_view, OpenApiResponse

from user.models import User, SocialAccount
from user.serializers import UserSerializer

from profiles.services import create_profile_for_user

from .serializers import (
    RegisterSerializer,
    LoginSerializer,
    EmailVerifySerializer,
    PasswordResetRequestSerializer,
    PasswordResetNewPasswordSerializer,
    PasswordResetVerifyCodeSerializer,
    ResendVerificationSerializer,
    GoogleLoginSerializer,
    LogoutSerializer,
    ChangePasswordSerializer,
)

from .utils import (
    send_verification_email,
    send_password_reset_email,
    log_action,
)

from .throttles import (
    LoginRateThrottle,
    RegisterRateThrottle,
    PasswordResetRateThrottle,
)


def get_tokens_for_user(user):
    refresh = RefreshToken.for_user(user)

    return {
        "refresh": str(refresh),
        "access": str(refresh.access_token),
    }


@extend_schema(
    summary="Register with email and password",
    description=(
        "Creates a new account using email/password. No login tokens are "
        "returned — the account must be verified via the emailed code "
        "before logging in."
    ),
    request=RegisterSerializer,
    responses={
        201: OpenApiResponse(description="Account created. Check email for a verification code."),
        400: OpenApiResponse(description="Email already registered, or invalid input."),
    },
    tags=["auth"],
)
class RegisterView(generics.CreateAPIView):
    permission_classes = [AllowAny]
    serializer_class = RegisterSerializer
    throttle_classes = [RegisterRateThrottle]

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        user = serializer.save()

        email_data = send_verification_email(user)

        log_action(
            request,
            "authentication.register",
            user=user
        )

        response_data = {
            "user": UserSerializer(user).data,
            "detail": (
                "Registration successful. "
                "Please check your email for a verification code "
                "before logging in."
            ),
        }

        if settings.EMAIL_DEV_MODE:
            response_data["dev_verification"] = email_data

        return Response(
            response_data,
            status=status.HTTP_201_CREATED
        )


@extend_schema(
    summary="Log in with email and password",
    description=(
        "Authenticates a user and returns JWT access/refresh tokens. "
        "Fails with a specific error code if the account's email has "
        "not been verified yet."
    ),
    request=LoginSerializer,
    responses={
        200: OpenApiResponse(description="Login successful. Returns user data and JWT tokens."),
        400: OpenApiResponse(description="Invalid credentials, disabled account, or unverified email."),
    },
    tags=["auth"],
)
class LoginView(generics.GenericAPIView):
    permission_classes = [AllowAny]
    serializer_class = LoginSerializer
    throttle_classes = [LoginRateThrottle]

    def post(self, request):
        serializer = self.get_serializer(data=request.data)

        try:
            serializer.is_valid(raise_exception=True)

        except serializers.ValidationError:
            log_action(
                request,
                "authentication.login.failed"
            )

            raise

        user = serializer.validated_data["user"]

        tokens = get_tokens_for_user(user)

        log_action(
            request,
            "authentication.login.success",
            user=user
        )

        return Response(
            {
                "user": UserSerializer(user).data,
                "tokens": tokens,
            },
            status=status.HTTP_200_OK
        )


@extend_schema(
    summary="Verify email address",
    description=(
        "Confirms an account's email using the 6-digit code sent to "
        "that address. Codes expire after 15 minutes and are single-use."
    ),
    request=EmailVerifySerializer,
    responses={
        200: OpenApiResponse(description="Email verified successfully."),
        400: OpenApiResponse(description="Invalid, expired, or already-used code."),
    },
    tags=["auth"],
)
class VerifyEmailView(generics.GenericAPIView):
    permission_classes = [AllowAny]
    serializer_class = EmailVerifySerializer

    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        user = serializer.validated_data["user"]

        user.is_email_verified = True

        user.save(
            update_fields=["is_email_verified"]
        )

        create_profile_for_user(user)

        log_action(
            request,
            "authentication.verify_email",
            user=user
        )

        return Response(
            {
                "detail": "Email verified successfully."
            },
            status=status.HTTP_200_OK
        )


@extend_schema(
    summary="Resend verification code",
    description=(
        "Sends a new verification code if the account exists and is "
        "still unverified. Always returns 200 regardless of whether the "
        "email exists, to avoid leaking which emails are registered. "
        "Any previously issued, unused code is invalidated."
    ),
    request=ResendVerificationSerializer,
    responses={200: OpenApiResponse(description="Generic confirmation message (see description).")},
    tags=["auth"],
)
class ResendVerificationEmailView(generics.GenericAPIView):
    permission_classes = [AllowAny]
    serializer_class = ResendVerificationSerializer
    throttle_classes = [RegisterRateThrottle]

    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        email = serializer.validated_data["email"]

        response_data = {
            "detail": (
                "If an account with that email exists and is "
                "unverified, a new verification code has been sent."
            )
        }

        try:
            user = User.objects.get(
                email__iexact=email,
                registration_method="email"
            )

            if not user.is_email_verified:

                email_data = send_verification_email(user)
                log_action(
                    request,
                    "authentication.resend_verification",
                    user=user
                )

                if settings.EMAIL_DEV_MODE:
                    response_data["dev_verification"] = email_data

        except User.DoesNotExist:
            pass

        return Response(
            response_data,
            status=status.HTTP_200_OK
        )


@extend_schema(
    summary="Request a password reset",
    description=(
        "Sends a password reset code if the account exists. Always "
        "returns 200 regardless of whether the email exists, to avoid "
        "leaking which emails are registered. Does not apply to Google "
        "accounts."
    ),
    request=PasswordResetRequestSerializer,
    responses={200: OpenApiResponse(description="Generic confirmation message (see description).")},
    tags=["auth"],
)
class PasswordResetRequestView(generics.GenericAPIView):
    permission_classes = [AllowAny]
    serializer_class = PasswordResetRequestSerializer
    throttle_classes = [PasswordResetRateThrottle]

    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        email = serializer.validated_data["email"]

        response_data = {
            "detail": (
                "If an account with that email exists, "
                "a reset code has been sent."
            )
        }

        try:
            user = User.objects.get(
                email__iexact=email,
                registration_method="email"
            )

            email_data = send_password_reset_email(user)

            log_action(
                request,
                "authentication.password_reset_request",
                user=user
            )

            if settings.EMAIL_DEV_MODE:
                response_data["dev_reset"] = email_data

        except User.DoesNotExist:
            pass

        return Response(
            response_data,
            status=status.HTTP_200_OK
        )


@extend_schema(
    summary="Verify a password reset code",
    description=(
        "Step 2 of password reset: checks the 6-digit code sent to the "
        "user's email. On success, returns a short-lived reset_token "
        "(separate from login JWTs) that the app uses on the next screen "
        "to actually set the new password — the code itself is not "
        "needed again."
    ),
    request=PasswordResetVerifyCodeSerializer,
    responses={
        200: OpenApiResponse(description="Code valid. Returns a reset_token for the next step."),
        400: OpenApiResponse(description="Invalid, expired, or already-used code."),
    },
    tags=["auth"],
)
class PasswordResetVerifyCodeView(generics.GenericAPIView):
    permission_classes = [AllowAny]
    serializer_class = PasswordResetVerifyCodeSerializer
    throttle_classes = [PasswordResetRateThrottle]

    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        otp = serializer.validated_data["otp"]
        user = serializer.validated_data["user"]

        reset_token = otp.issue_reset_token(ttl_minutes=10)

        log_action(
            request,
            "authentication.password_reset_code_verified",
            user=user
        )

        return Response(
            {
                "detail": "Code verified. Use the reset_token below to set your new password.",
                "reset_token": reset_token,
            },
            status=status.HTTP_200_OK
        )


@extend_schema(
    summary="Set new password after reset verification",
    description=(
        "Step 3 of password reset: sets the new password using the "
        "reset_token returned by the verify-code step. The token is "
        "single-use and expires after 10 minutes."
    ),
    request=PasswordResetNewPasswordSerializer,
    responses={
        200: OpenApiResponse(description="Password reset successful."),
        400: OpenApiResponse(description="Invalid/expired reset_token, or password fails validation rules."),
    },
    tags=["auth"],
)
class PasswordResetSetNewPasswordView(generics.GenericAPIView):
    permission_classes = [AllowAny]
    serializer_class = PasswordResetNewPasswordSerializer
    throttle_classes = [PasswordResetRateThrottle]

    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        otp = serializer.validated_data["otp"]
        user = serializer.validated_data["user"]

        user.set_password(serializer.validated_data["new_password"])
        user.save(update_fields=["password"])

        otp.used = True
        otp.save(update_fields=["used"])

        log_action(
            request,
            "authentication.password_reset_confirm",
            user=user
        )

        return Response(
            {"detail": "Password reset successful."},
            status=status.HTTP_200_OK
        )


@extend_schema(
    summary="Log in / register with Google",
    description=(
        "Verifies a Google ID token server-side, then either logs in an "
        "existing linked account or creates a new one. Google accounts "
        "are automatically marked as email-verified. Returns the same "
        "JWT token shape as the regular login endpoint."
    ),
    request=GoogleLoginSerializer,
    responses={
        200: OpenApiResponse(description="Login/registration successful. Returns user data and JWT tokens."),
        400: OpenApiResponse(description="Invalid Google token, or email already registered via another method."),
    },
    tags=["auth"],
)
class GoogleLoginView(generics.GenericAPIView):
    permission_classes = [AllowAny]
    serializer_class = GoogleLoginSerializer
    throttle_classes = [LoginRateThrottle]

    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        google_uid = serializer.validated_data["google_uid"]
        email = serializer.validated_data["email"]
        first_name = serializer.validated_data["first_name"]
        last_name = serializer.validated_data["last_name"]

        try:
            social_account = SocialAccount.objects.select_related(
                "user"
            ).get(provider_uid=google_uid)

            user = social_account.user

        except SocialAccount.DoesNotExist:

            try:
                user = User.objects.get(
                    email__iexact=email
                )
                if user.registration_method != "google":
                    raise serializers.ValidationError(
                        "An account with this email already exists. "
                        "Please log in using your existing method."
                    )

            except User.DoesNotExist:

                user = User.objects.create_user(
                    email=email,
                    first_name=first_name,
                    last_name=last_name,
                    registration_method="google",
                )

                user.is_email_verified = True
                user.save(
                    update_fields=["is_email_verified"]
                )

                create_profile_for_user(user)

            SocialAccount.objects.create(
                user=user,
                provider_uid=google_uid,
            )

        if not user.is_active:
            raise serializers.ValidationError(
                "This account is disabled."
            )

        tokens = get_tokens_for_user(user)

        log_action(
            request,
            "authentication.google_login.success",
            user=user,
        )

        return Response(
            {
                "user": UserSerializer(user).data,
                "tokens": tokens,
            },
            status=status.HTTP_200_OK,
        )


@extend_schema(
    summary="Link a Google account to the signed-in account",
    description=(
        "Verifies a Google ID token server-side, then links that Google "
        "account to the currently signed-in user — letting them log in "
        "with either their password or Google afterward. Requires the "
        "Google account's email to match the signed-in account's email. "
        "Fails if that Google account is already linked to a different "
        "Music Room account."
    ),
    request=GoogleLoginSerializer,
    responses={
        200: OpenApiResponse(description="Google account linked (or already linked to this account)."),
        400: OpenApiResponse(description="Invalid Google token, email mismatch, or already linked elsewhere."),
    },
    tags=["auth"],
)
class GoogleLinkView(generics.GenericAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = GoogleLoginSerializer
    throttle_classes = [LoginRateThrottle]

    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        google_uid = serializer.validated_data["google_uid"]
        google_email = serializer.validated_data["email"]

        if google_email.lower() != request.user.email.lower():
            raise serializers.ValidationError(
                "This Google account's email must match your account email to link it."
            )

        existing = SocialAccount.objects.filter(provider_uid=google_uid).first()
        if existing:
            if existing.user_id == request.user.id:
                return Response(
                    {
                        "user": UserSerializer(request.user).data,
                        "detail": "This Google account is already linked.",
                    },
                    status=status.HTTP_200_OK,
                )
            raise serializers.ValidationError(
                "This Google account is already linked to a different account."
            )

        SocialAccount.objects.create(user=request.user, provider_uid=google_uid)

        log_action(
            request,
            "authentication.google_link",
            user=request.user,
        )

        return Response(
            {
                "user": UserSerializer(request.user).data,
                "detail": "Google account linked successfully.",
            },
            status=status.HTTP_200_OK,
        )


@extend_schema(
    summary="Log out",
    description=(
        "Blacklists the provided refresh token so it can no longer be "
        "used to obtain new access tokens. Requires a valid access token "
        "in the Authorization header."
    ),
    request=LogoutSerializer,
    responses={
        205: OpenApiResponse(description="Logout successful."),
        400: OpenApiResponse(description="Invalid or already-blacklisted refresh token."),
    },
    tags=["auth"],
)
class LogoutView(generics.GenericAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = LogoutSerializer

    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        try:
            token = RefreshToken(serializer.validated_data["refresh"])
            token.blacklist()
        except TokenError:
            raise serializers.ValidationError("Invalid or expired refresh token.")

        log_action(
            request,
            "authentication.logout",
            user=request.user
        )

        return Response(status=status.HTTP_205_RESET_CONTENT)
    
@extend_schema(
    summary="Change password (while logged in)",
    description=(
        "Changes the current user's password. Requires the correct "
        "current password as proof of identity — different from the "
        "forgot-password flow, which uses an emailed code instead."
    ),
    request=ChangePasswordSerializer,
    responses={
        200: OpenApiResponse(description="Password changed successfully."),
        400: OpenApiResponse(description="Current password incorrect, or new password fails validation rules."),
    },
    tags=["auth"],
)

class ChangePasswordView(generics.GenericAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = ChangePasswordSerializer
 
    def post(self, request):
        serializer = self.get_serializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
 
        user = request.user
        user.set_password(serializer.validated_data["new_password"])
        user.save(update_fields=["password"])
 
        log_action(
            request,
            "authentication.password_changed",
            user=user
        )
 
        return Response(
            {"detail": "Password changed successfully."},
            status=status.HTTP_200_OK
        )