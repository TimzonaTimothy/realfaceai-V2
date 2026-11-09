from django.urls import path, re_path
from .views import *
from django.conf import settings
from django.conf.urls.static import static
from django.views.static import serve

app_name = 'core'

urlpatterns = [
    path('', product_list, name='product_list'),
    path('<slug:slug>/', product_detail, name='product_detail'),
    path('purchase/<slug:slug>/', choose_payment_method, name='choose_payment_method'),
    path('payment_address/<slug:slug>/<int:payment_method_id>/', payment_address, name='payment_address'),
    path('upload_payment_proof/<slug:slug>/<int:payment_method_id>/', upload_payment_proof, name='upload_payment_proof'),
    path('order_summary/<str:payment_id>/', order_summary, name='order_summary'),
]+ static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
urlpatterns += static(settings.STATIC_URL, document_root=settings.STATIC_ROOT)

