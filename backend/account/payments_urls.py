from django.urls import path
from .payment_views import (
    CreditPacksView,
    CreatePaymentView,
    PaymentHistoryView,
    PaymentStatusView,
)

urlpatterns = [
    path("packs/",                      CreditPacksView.as_view(),    name="credit_packs"),
    path("create/",                     CreatePaymentView.as_view(),  name="create_payment"),
    path("",                            PaymentHistoryView.as_view(), name="payment_history"),
    path("<str:payment_id>/status/",    PaymentStatusView.as_view(),  name="payment_status"),
]
