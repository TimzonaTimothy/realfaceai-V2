from decimal import Decimal
from django.contrib.auth.password_validation import validate_password
from rest_framework import serializers
from .models import Account, UserProfile, UsageLog


class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(
        write_only=True,
        min_length=8,
        validators=[validate_password],
    )
    password2 = serializers.CharField(write_only=True)

    class Meta:
        model = Account
        fields = ["id", "email", "password", "password2"]

    def validate(self, attrs):
        if attrs["password"] != attrs["password2"]:
            raise serializers.ValidationError({"password": "Passwords do not match."})
        return attrs

    def create(self, validated_data):
        validated_data.pop("password2")
        user = Account.objects.create_user(
            email=validated_data["email"],
            password=validated_data["password"],
        )
        # Auto-create UserProfile with 0 credits
        profile, created = UserProfile.objects.get_or_create(user=user)
        if created:
            profile.credits = Decimal("50")
            profile.save(update_fields=["credits"])
        return user


class UserProfileSerializer(serializers.ModelSerializer):
    credits = serializers.SerializerMethodField()
    plan = serializers.SerializerMethodField()
    account_status = serializers.SerializerMethodField()

    class Meta:
        model = Account
        fields = [
            "id",
            "email",
            "credits",
            "plan",
            "is_active",
            "date_joined",
            "account_status",
        ]
        read_only_fields = fields

    def get_credits(self, obj):
        profile, _ = UserProfile.objects.get_or_create(user=obj)
        return float(profile.credits)

    def get_plan(self, obj):
        profile, _ = UserProfile.objects.get_or_create(user=obj)
        return profile.plan

    def get_account_status(self, obj):
        # {status: active|frozen|suspended, reason, expires_at, changed_at, support_email}
        from .account_status import status_payload
        return status_payload(obj)


class UsageLogSerializer(serializers.ModelSerializer):
    class Meta:
        model = UsageLog
        fields = [
            "id",
            "endpoint",
            "model_used",
            "credits_used",
            "timestamp",
            "metadata",
        ]
        read_only_fields = fields