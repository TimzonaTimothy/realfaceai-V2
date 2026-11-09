class CreditPack {
  final String id;
  final String label;
  final int    credits;
  final String priceUsd;
  final bool   popular;
  final String description;
  final int    streamingMinutes; // convenience field from backend

  CreditPack({
    required this.id,
    required this.label,
    required this.credits,
    required this.priceUsd,
    required this.popular,
    required this.description,
    this.streamingMinutes = 0,
  });

  factory CreditPack.fromJson(Map<String, dynamic> json) {
    return CreditPack(
      id:                json['id']          ?? '',
      label:             json['label']        ?? '',
      credits:           json['credits']      ?? 0,
      priceUsd:          json['price_usd']?.toString() ?? '0.00',
      popular:           json['popular']      ?? false,
      description:       json['description']  ?? '',
      streamingMinutes:  json['streaming_minutes'] ?? 0,
    );
  }
}

class Payment {
  final String  id;
  final String  packId;
  final String  packLabel;
  final String  amountUsd;
  final int     creditsToAdd;
  final String  currency;
  final String  gateway;   // "crypto" | "flutterwave"
  final String  status;
  final String? paymentUrl;
  final String  createdAt;
  final String? confirmedAt;

  // Wallet the user was told to pay into (stored server-side).
  final String  walletAddress;
  final String  walletLabel;

  // Proof-of-payment info
  final int     proofCount;
  final String? lastProofAt;
  /// null  → no proof sent yet
  /// true  → the latest proof image is stored on the server
  /// false → a proof was attempted but the image never arrived (re-upload)
  final bool?   lastProofHasImage;

  Payment({
    required this.id,
    this.packId = '',
    required this.packLabel,
    required this.amountUsd,
    required this.creditsToAdd,
    required this.currency,
    required this.gateway,
    required this.status,
    this.paymentUrl,
    required this.createdAt,
    this.confirmedAt,
    this.walletAddress = '',
    this.walletLabel = '',
    this.proofCount = 0,
    this.lastProofAt,
    this.lastProofHasImage,
  });

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id:                json['payment_id']?.toString() ?? '',
      packId:            json['pack_id']?.toString() ?? '',
      packLabel:         json['pack_label']    ?? '',
      amountUsd:         json['amount_usd']?.toString() ?? '0.00',
      creditsToAdd:      json['credits_to_add'] ?? 0,
      currency:          json['currency']      ?? '',
      gateway:           json['gateway']       ?? 'crypto',
      status:            json['status']        ?? 'waiting',
      paymentUrl:        json['payment_url'],
      createdAt:         json['created_at']?.toString() ?? '',
      confirmedAt:       json['confirmed_at']?.toString(),
      walletAddress:     json['wallet_address']?.toString() ?? '',
      walletLabel:       json['wallet_label']?.toString() ?? '',
      proofCount:        (json['proof_count'] as num?)?.toInt() ?? 0,
      lastProofAt:       json['last_proof_at']?.toString(),
      lastProofHasImage: json['last_proof_has_image'] as bool?,
    );
  }

  bool get isConfirmed   => status == 'confirmed';
  bool get isPending     => status == 'waiting' || status == 'confirming';
  bool get isCrypto      => gateway == 'crypto';
  bool get isFlutterwave => gateway == 'flutterwave';

  bool get hasProof        => proofCount > 0;
  bool get proofReceived   => hasProof && lastProofHasImage == true;
  bool get proofNeedsRetry => hasProof && lastProofHasImage == false;
}

/// One proof submission for a payment (GET /auth/payments/<id>/proofs/).
class PaymentProofInfo {
  final int     id;
  final String  submittedAt;
  final String  txHash;
  final String  notes;
  final bool    hasImage;
  final String? imagePath; // relative to kBaseUrl
  final String  originalFilename;

  PaymentProofInfo({
    required this.id,
    required this.submittedAt,
    required this.txHash,
    required this.notes,
    required this.hasImage,
    required this.imagePath,
    required this.originalFilename,
  });

  factory PaymentProofInfo.fromJson(Map<String, dynamic> json) {
    return PaymentProofInfo(
      id:               (json['id'] as num?)?.toInt() ?? 0,
      submittedAt:      json['submitted_at']?.toString() ?? '',
      txHash:           json['tx_hash']?.toString() ?? '',
      notes:            json['notes']?.toString() ?? '',
      hasImage:         json['has_image'] == true,
      imagePath:        json['image_path']?.toString(),
      originalFilename: json['original_filename']?.toString() ?? '',
    );
  }
}