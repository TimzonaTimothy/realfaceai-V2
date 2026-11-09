from django.shortcuts import render

# Create your views here.
from django.shortcuts import render, get_object_or_404, redirect
from django.contrib.auth.decorators import login_required
from .models import *
from django.contrib import messages
from django.contrib.auth import get_user_model
import random
from django.core.mail import send_mail

User = get_user_model()

def product_list(request):
    products = Product.objects.all()
    return render(request, 'product_list.html', {'products': products})

def product_detail(request, slug):
    product = get_object_or_404(Product, slug=slug)
    return render(request, 'product_detail.html', {'product': product})


@login_required(login_url = '/account/sign_in')
def choose_payment_method(request, slug):
    product = get_object_or_404(Product, slug=slug)
    payment_methods = PaymentMethod.objects.all()  # All available methods
    
    if request.method == 'POST':
        payment_method_id = request.POST.get('payment_method')
        payment_method = PaymentMethod.objects.get(id=payment_method_id)
        
        # Redirect to the next page where the address will be shown
        return redirect('core:payment_address', slug=product.slug, payment_method_id=payment_method.id)

    return render(request, 'choose_payment_method.html', {
        'product': product,
        'payment_methods': payment_methods
    })


@login_required(login_url='/account/sign_in')
def payment_address(request, slug, payment_method_id):
    product = get_object_or_404(Product, slug=slug)
    payment_method = get_object_or_404(PaymentMethod, id=payment_method_id)
    
    # Assume `payment_method.address` contains the crypto address for payment
    payment_addresses = PaymentMethodAddress.objects.filter(name=payment_method)
    
    # Randomly pick one address if available, otherwise set to None
    payment_address = random.choice(payment_addresses).address if payment_addresses.exists() else None
    
    price = product.price  # Product price to display as payment amount
    
    if request.method == 'POST':
        # Here, you'd confirm payment (could be by some API, or manual validation)
        return redirect('core:upload_payment_proof', slug=slug, payment_method_id=payment_method_id)
    
    return render(request, 'payment_address.html', {
        'product': product,
        'payment_method': payment_method,
        'payment_address': payment_address,
        'price': price
    })

@login_required(login_url='/account/sign_in')
def upload_payment_proof(request, slug, payment_method_id):
    product = get_object_or_404(Product, slug=slug)
    payment_method = get_object_or_404(PaymentMethod, id=payment_method_id)
    
    if request.method == 'POST':
        # Save the payment proof (e.g., an uploaded image or transaction hash)
        payment_proof = request.FILES.get('payment_proof')
        payment_address = request.POST.get('payment_address')
        
        # You could save these details in the Order or Payment model
        # Example:
        # Create a Payment after the order
        payment = Payment.objects.create(
            user=request.user,
            product=product,
            amount=product.price,
            payment_method=payment_method,
            crypto_address=payment_address,
            payment_proof=payment_proof,  # Save the uploaded payment proof
            status='pending',  # Or 'confirmed' as per the process
        )
        payment.save();
        send_mail(
            'New Payment Alert',
            'Login to admin to verify',
            'support@deepfakessoftwares.com',  # From Email
            ['support@deepfakessoftwares.com','vitalisosuchukwu5@gmail.com','vitalischima77@gmail.com'],  # To Email
            fail_silently=False,
        )
        # user = request.user
        # product=product
        # mail_subject_ = 'New Payment'
        # message_ = f'The user {user} made a payment for {product}.'
        # send_mail(mail_subject_, message_, 'support@deepfakessoftwares.com', ['support@deepfakessoftwares.com'], fail_silently=False)

        
        # Redirect to a confirmation page or order summary page
        messages.success(request, 'Success! Your order has been created. Please wait while we verify the payment.')
        return redirect('core:order_summary', payment_id=payment.id)
    
    return render(request, 'upload_payment_proof.html', {
        'product': product,
        'payment_method': payment_method
    })


@login_required(login_url='/account/sign_in')
def order_summary(request, payment_id):
    payment = get_object_or_404(Payment, id=payment_id, user=request.user)

    # You can also include other details if necessary, like payment method and price.
    payment_method = PaymentMethod.objects.get(id=payment.payment_method.id) if payment.payment_method else None
    product = Product.objects.get(id=payment.product.id)
    
    return render(request, 'order_summary.html', {
        'payment': payment,
        'product': product,
        'payment_method': payment_method,
    })