"""deep URL Configuration

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/3.2/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.contrib import admin
from django.urls import path,include, reverse_lazy
from django.conf import settings
from django.conf.urls.static import static
from .views import *
from account.views import download_app_view as download_app
from account.views import serve_download_file
from django.views.generic import RedirectView
from .seo_views import robots_txt, sitemap_xml, llms_txt

urlpatterns = [
    path('admin/', admin.site.urls),
    path('', landing, name='home'),
    # /home used to serve a duplicate of /download/ — 301 it so Google sees one URL
    path('home', RedirectView.as_view(url='/', permanent=True)),
    path('robots.txt', robots_txt),
    path('sitemap.xml', sitemap_xml),
    path('llms.txt', llms_txt),
    path('terms/', terms_view, name='terms'),
    path('privacy/', privacy_view, name='privacy'),
    path('consent/', consent_view, name='consent'),
    path('download/', download_app, name='download_app'),
    path('download/file/', serve_download_file, name='download_file'),
    # api urls
    path("api/v1/auth/",     include("account.urls")),
    # # Added:
    path("api/v1/payments/deposit/", include("account.deposit_urls")),
    path("api/v1/payments/", include("account.payments_urls")),
    path("api/v1/keys/",     include("api.urls")),
    path("api/v1/app/", include("api.urls")),
    path("api/v1/stream/",   include("streaming.urls")),
]+ static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT) + static(settings.STATIC_URL, document_root=settings.STATIC_ROOT)
