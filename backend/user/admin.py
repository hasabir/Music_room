# user/admin.py
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from .models import User
from .models import ActionLog
from .models import Notification

admin.site.register(ActionLog)
admin.site.register(Notification)
class UserAdmin(BaseUserAdmin):
    ordering = ['username']
    list_display = ['username', 'email', 'first_name', 'last_name', 'registration_method', 'is_email_verified', 'subscription_tier', 'is_staff']
    search_fields = ['username', 'email', 'first_name', 'last_name']
    fieldsets = (
        (None, {'fields': ('email', 'password')}),
        ('Personal info', {'fields': ('username', 'first_name', 'last_name', 'registration_method', 'is_email_verified', 'subscription_tier', 'subscription_expires_at')}),
        ('Permissions', {'fields': ('is_active', 'is_staff', 'is_superuser', 'groups', 'user_permissions')}),
        ('Important dates', {'fields': ('last_login', 'date_joined')}),
    )
    add_fieldsets = (
        (None, {
            'classes': ('wide',),
            'fields': ('email', 'password1', 'password2'),
        }),
    )

admin.site.register(User, UserAdmin)
