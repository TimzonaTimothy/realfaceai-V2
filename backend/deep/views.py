from django.shortcuts import render, redirect,get_object_or_404
from django.core.exceptions import ObjectDoesNotExist
from django.contrib import messages
from django.http import HttpResponseRedirect, HttpResponse,JsonResponse,HttpRequest
from django.contrib.sites.shortcuts import get_current_site
from django.template.loader import render_to_string
from django.utils.http import urlsafe_base64_encode, urlsafe_base64_decode
from django.utils.encoding import force_bytes
from django.contrib.auth.tokens import default_token_generator
from django.core.mail import EmailMessage
from django.contrib.auth import get_user_model
from django.core.mail import send_mail
from django.contrib import auth
from django.urls import reverse_lazy,reverse
from django.contrib.auth.decorators import login_required
from django.contrib.auth import logout
import secrets
from django.contrib.auth import login
from account.models import *
from django.shortcuts import render, redirect
from django.contrib import messages
from django.utils import timezone
from core.models import *


def home(request):
    products = Product.objects.all()
    return render(request, 'index-3.html', {'products': products})


def landing(request):
    from django.conf import settings
    return render(request, 'landing.html', {
        'credit_packs': settings.CREDIT_PACKS,
    })
    

def terms_view(request):
    return render(request, 'terms.html')

def privacy_view(request):
    return render(request, 'privacy.html')
    
def consent_view(request):
    return render(request, 'consent.html')

def support(request):
    return render(request, 'support.html', {})


def contact(request):
    if request.method == "POST":
        name = request.POST['full_name'] 
        email = request.POST['email']
        subject = request.POST['subject']
        message = request.POST['message']
        contact = Contact.objects.create(full_name=name,email=email,subject=subject,message=message)
        contact.save();
        messages.success(request, 'Your massage has been submitted ')
    return render(request, 'contact.html', {})


def newsletter_sub(request):
    if request.method == 'POST':
        email = request.POST.get('email')
        bot = request.POST.get('bot')
        if bot:
            return JsonResponse({'error': 'Bot detected'}, status=400)
        elif not email:
            return JsonResponse({'error': 'Email is required'}, status=400)
        elif Newsletter.objects.filter(email=email).exists():
            return JsonResponse({'error': 'Email already exists'}, status=400)
        else:
            newsletter = Newsletter(email=email)
            newsletter.save()
            return JsonResponse({'success': 'Email submitted successfully'})
