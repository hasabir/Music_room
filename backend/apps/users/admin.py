from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.utils.translation import gettext_lazy as _
from .models import User, Friendship, PasswordResetToken


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    """Admin interface for custom User model"""
    
    list_display = [
        'email', 'display_name', 'subscription_type',
        'email_verified', 'is_staff', 'is_active', 'created_at'
    ]
    list_filter = [
        'subscription_type', 'email_verified',
        'is_staff', 'is_active', 'created_at'
    ]
    search_fields = ['email', 'display_name', 'first_name', 'last_name']
    ordering = ['-created_at']
    
    fieldsets = (
        (None, {'fields': ('email', 'password')}),
        (_('Personal info'), {
            'fields': (
                'first_name', 'last_name', 'display_name',
                'avatar', 'bio', 'date_of_birth'
            )
        }),
        (_('Contact'), {
            'fields': ('phone_number', 'location')
        }),
        (_('Music Preferences'), {
            'fields': ('favorite_genres', 'favorite_artists', 'music_services')
        }),
        (_('Social Accounts'), {
            'fields': ('facebook_id', 'google_id')
        }),
        (_('Subscription'), {
            'fields': ('subscription_type', 'subscription_expires_at')
        }),
        (_('Verification'), {
            'fields': ('email_verified', 'email_verification_token')
        }),
        (_('Permissions'), {
            'fields': ('is_active', 'is_staff', 'is_superuser', 'groups', 'user_permissions')
        }),
        (_('Important dates'), {
            'fields': ('last_login', 'created_at', 'updated_at')
        }),
    )
    
    add_fieldsets = (
        (None, {
            'classes': ('wide',),
            'fields': (
                'email', 'password1', 'password2',
                'display_name', 'is_staff', 'is_active'
            ),
        }),
    )
    
    readonly_fields = ['created_at', 'updated_at', 'last_login', 'email_verification_token']


@admin.register(Friendship)
class FriendshipAdmin(admin.ModelAdmin):
    """Admin interface for Friendship model"""
    
    list_display = ['from_user', 'to_user', 'status', 'created_at', 'updated_at']
    list_filter = ['status', 'created_at']
    search_fields = ['from_user__email', 'to_user__email']
    ordering = ['-created_at']
    
    readonly_fields = ['created_at', 'updated_at']


@admin.register(PasswordResetToken)
class PasswordResetTokenAdmin(admin.ModelAdmin):
    """Admin interface for PasswordResetToken model"""
    
    list_display = ['user', 'token', 'created_at', 'used']
    list_filter = ['used', 'created_at']
    search_fields = ['user__email', 'token']
    ordering = ['-created_at']
    
    readonly_fields = ['token', 'created_at']

