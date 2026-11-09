from django.db import models
from account.models import Account
from django.template.loader import render_to_string
from django.core.mail import EmailMessage
from django.contrib.auth.models import User
from django.conf import settings

# Create your models here.
class Product(models.Model):
    name = models.CharField(max_length=255, unique=True)
    slug = models.SlugField(unique=True)
    description = models.TextField()
    link = models.CharField(max_length=255, unique=True, blank=True,null=True)
    password = models.CharField(max_length=100, blank=True, null=True)
    price = models.DecimalField(max_digits=10, decimal_places=2)
    image = models.ImageField(upload_to='products/', blank=True,null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.name


# class Order(models.Model):
    

#     user = models.ForeignKey(Account, on_delete=models.CASCADE, related_name="orders")
#     product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name="orders")
#     amount = models.DecimalField(max_digits=10, decimal_places=2)
#     status = models.CharField(max_length=10, choices=STATUS_CHOICES, default='pending')
#     created_at = models.DateTimeField(auto_now_add=True)
#     updated_at = models.DateTimeField(auto_now=True)

#     def __str__(self):
#         return f"Order {self.id} - {self.user.email} - {self.product.name} - {self.status}"

#     def save(self, *args, **kwargs):
#         if self.id:  # Update scenario
#             old = Order.objects.get(pk=self.id)

#             # Handle status changes
#             if old.status in ['pending', 'declined'] and self.status == 'confirmed':
#                 if self.user and self.amount:
#                     self.send_notification('mail/completed.html', 'Transaction Comfirmed')

#             elif old.status == 'pending' and self.status == 'declined':
#                 # Notify on transaction cancellation
#                 self.send_notification('mail/declined.html', 'Transaction Declined')

#         super(Order, self).save(*args, **kwargs)

#     def send_notification(self, template, subject):
#         if self.user and self.user.email:  # Check for valid sender and email
#             message = render_to_string(template, {
#                 'user': self.user,
#                 'product': self.product.name,
#                 'amount': self.amount,
#                 'status': self.status, 
#                 'date':self.created_at
#             })
#             send_email = EmailMessage(subject, message, to=[self.user.email])
#             send_email.content_subtype = "html"
#             send_email.send()


class PaymentMethod(models.Model):
    name = models.CharField(max_length=100)
  
    def __str__(self):
        return self.name
        
class PaymentMethodAddress(models.Model):
    name = models.ForeignKey(PaymentMethod, on_delete=models.CASCADE)
    address = models.CharField(max_length=200, null=True, blank=True)

    def __str__(self):
        return f"Crypto {self.name} - Address {self.address}"


import secrets

def generate_payment_id():
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    suffix = "".join(secrets.choice(alphabet) for _ in range(8))
    return f"PYM-{suffix}"
    
class Payment(models.Model):
    STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('confirmed', 'Confirmed'),
        ('declined', 'Declined'),
    ]
    
    payment_id = models.CharField(
        max_length=20,
        unique=True,
        editable=False,
        db_index=True,
        default=generate_payment_id,
        help_text="Random public payment reference (e.g. PYM-4X7B2QQK).",
    )

    user = models.ForeignKey(Account, on_delete=models.CASCADE)
    product = models.ForeignKey(Product, on_delete=models.CASCADE)
    amount = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    payment_method = models.ForeignKey(PaymentMethod, on_delete=models.CASCADE)
    crypto_address = models.CharField(max_length=255,null=True, blank=True)
    payment_proof = models.ImageField(upload_to='payment_proofs/', null=True, blank=True)
    status = models.CharField(max_length=10, choices=STATUS_CHOICES, default='pending',null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, null=True, blank=True)
    updated_at = models.DateTimeField(auto_now=True,null=True, blank=True)
    
    def __str__(self):
        return f"Payment {self.id} - {self.user.email} for {self.product.name}"

    def save(self, *args, **kwargs):
        if not self.id:  # New payment — guard against a payment_id collision
            while Payment.objects.filter(payment_id=self.payment_id).exists():
                self.payment_id = generate_payment_id()
                
        if self.id:  # Update scenario
            old = Payment.objects.get(pk=self.id)

            # Handle status changes
            if old.status in ['pending', 'declined'] and self.status == 'confirmed':
                if self.user and self.amount:
                    self.send_notification('mail/completed.html', 'Transaction Comfirmed')

            elif old.status == 'pending' and self.status == 'declined':
                # Notify on transaction cancellation
                self.send_notification('mail/declined.html', 'Transaction Declined')

        super(Payment, self).save(*args, **kwargs)

    # def send_notification(self, template, subject):
    #     if self.user and self.user.email:  # Check for valid sender and email
    #         message = render_to_string(template, {
    #             'user': self.user,
    #             'product': self.product.name,
    #             'amount': self.amount,
    #             'status': self.status, 
    #             'date':self.created_at, 
    #             'download_link': self.product.link,
    #             'password': self.product.password,
    #         })
    #         send_email = EmailMessage(subject, message,from_email=settings.DEFAULT_FROM_EMAIL,  to=[self.user.email])
    #         send_email.content_subtype = "html"
    #         send_email.send()
    
    def send_notification(self, template, subject):
        if self.user and self.user.email:
            message = render_to_string(template, {
                'user': self.user,
                'product': self.product.name,
                'amount': self.amount,
                'status': self.status,
                'date': self.created_at,
                'download_link': self.product.link,
                'password': self.product.password,
            })
            email = EmailMessage(
                subject,
                message,
                from_email=settings.DEFAULT_FROM_EMAIL,
                to=[self.user.email],
                reply_to=[settings.SUPPORT_EMAIL],
            )
            email.content_subtype = 'html'
            email.send(fail_silently=True)

class Contact(models.Model):
    full_name = models.CharField(max_length=200,null=True,blank=True)
    email = models.EmailField(max_length=200,null=True,blank=True)
    subject = models.CharField(max_length=200,null=True,blank=True)
    message = models.TextField(max_length=500,null=True,blank=True)

    class Meta:
        verbose_name = 'Contact'
        verbose_name_plural = 'Contacts'

    def __str__(self):
        return str(self.full_name)


class Newsletter(models.Model):
    email = models.EmailField(blank=True, null=True,unique=True)
    created_at = models.DateTimeField(auto_now_add=True)
    
    def __str__(self):
        return str(self.email)