from django.contrib import admin
from .models import *
from django.contrib.auth.admin import UserAdmin

# Register your models here.
class ProductAdmin(admin.ModelAdmin):
    list_display = ('name', 'price', 'created_at')
    list_display_links = ('name', 'price', 'created_at',)
    ordering = ('-created_at',)
    prepopulated_fields = {'slug': ('name',)}

    filter_horizontal = ()
    list_filter = ('created_at',)
    list_per_page = 25
    search_fields = ('name', 'slug')

# admin.site.register(Product, ProductAdmin)


class PaymentAdmin(admin.ModelAdmin):
    list_display = ('user', 'product', 'amount','status')
    list_display_links = ('user', 'product', 'amount',)
    ordering = ('-created_at',)
    
    filter_horizontal = ()
    list_filter = ('created_at',)
    list_per_page = 25
    search_fields = ('user', 'product','status')

# admin.site.register(Payment, PaymentAdmin)

# admin.site.register(PaymentMethod)

class PaymentMethodAddressAdmin(admin.ModelAdmin):
    list_display = ('name', 'address')
    list_display_links = ('name', 'address',)
    
    filter_horizontal = ()
    list_filter = ('name',)
    list_per_page = 25
    search_fields = ('name', 'address')

# admin.site.register(PaymentMethodAddress, PaymentMethodAddressAdmin)
admin.site.register(Contact)
admin.site.register(Newsletter)