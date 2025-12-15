class ParsedReceipt {
  String? storeName;
  String? date;
  List<ReceiptItem> items;
  double? subtotal;
  double? tax;
  double? total;
  double parsingConfidence;

  ParsedReceipt({
    this.storeName,
    this.date,
    required this.items,
    this.subtotal,
    this.tax,
    this.total,
    required this.parsingConfidence,
  });

  factory ParsedReceipt.fromJson(Map<String, dynamic> json) {
    return ParsedReceipt(
      storeName: json['storeName'],
      date: json['date'],
      items: (json['items'] as List?)
          ?.map((item) => ReceiptItem.fromJson(item))
          .toList() ?? [],
      subtotal: json['subtotal']?.toDouble(),
      tax: json['tax']?.toDouble(),
      total: json['total']?.toDouble(),
      parsingConfidence: (json['parsingConfidence'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'storeName': storeName,
    'date': date,
    'items': items.map((item) => item.toJson()).toList(),
    'subtotal': subtotal,
    'tax': tax,
    'total': total,
    'parsingConfidence': parsingConfidence,
  };
}

class ReceiptItem {
  String name;
  double? price;
  double? qty;
  double confidence;
  bool isAccepted; // User can accept/reject

  ReceiptItem({
    required this.name,
    this.price,
    this.qty,
    required this.confidence,
    this.isAccepted = true,
  });

  factory ReceiptItem.fromJson(Map<String, dynamic> json) {
    return ReceiptItem(
      name: json['name'] ?? 'Unknown',
      price: json['price']?.toDouble(),
      qty: json['qty']?.toDouble() ?? 1.0,
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      isAccepted: true,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'price': price,
    'qty': qty,
    'confidence': confidence,
  };
}

class BackendResponse {
  bool success;
  ParsedReceipt? receipt;
  String? error;
  int processingTimeMs;
  String method;

  BackendResponse({
    required this.success,
    this.receipt,
    this.error,
    required this.processingTimeMs,
    required this.method,
  });

  factory BackendResponse.fromJson(Map<String, dynamic> json) {
    return BackendResponse(
      success: json['success'] ?? false,
      receipt: json['receipt'] != null
          ? ParsedReceipt.fromJson(json['receipt'])
          : null,
      error: json['error'],
      processingTimeMs: json['processingTimeMs'] ?? 0,
      method: json['method'] ?? 'unknown',
    );
  }
}