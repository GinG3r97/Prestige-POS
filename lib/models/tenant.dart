import 'package:uuid/uuid.dart';

import 'catalog.dart';
import 'employee.dart';

const _uuid = Uuid();

class Tenant {
  final String id;
  String businessName;
  String address;
  String currency;
  String timezone;
  /// Public URL of the store's uploaded logo (in the product-images bucket).
  /// Shown on the login screen, top bar, and printed receipts. Null = use the
  /// default storefront mark.
  String? logoUrl;
  /// Optional extra lines printed under the business name on receipts (e.g.
  /// TIN, tagline). Null/empty = nothing extra.
  String? receiptHeader;
  /// Optional footer printed at the bottom of receipts (thank-you / promo /
  /// return policy). Null/empty falls back to a default thank-you line.
  String? receiptFooter;
  /// Alignment for the custom header/footer text — 'center' or 'left'.
  String receiptAlign;
  /// Receipt layout template (1 Standard, 2 Compact, 3 Official).
  int receiptTemplate;
  /// Prep-ticket layout template (1 Standard, 2 Minimal, 3 Detailed).
  int ticketTemplate;
  /// Blank lines fed after each printed ticket (paper-save / tear-off gap).
  int printTailLines;
  /// Built-in printer font: 'a' = normal, 'b' = small/condensed.
  String printFont;
  /// Store-wide master switch for inventory tracking. When false, NO product
  /// deducts stock or blocks selling (per-product [CafeItem.trackInventory] is
  /// ignored). Lets a store sell freely until they're ready to use inventory.
  bool inventoryTrackingEnabled;

  // ── BIR (Bureau of Internal Revenue) registration — printed on invoices ──
  /// When true the invoice shows the 12% VAT breakdown; when false it prints
  /// the Non-VAT note ("NOT VALID FOR CLAIM OF INPUT TAX").
  bool vatRegistered;
  String? tin;
  String branchCode;
  /// Machine Identification Number.
  String? birMin;
  /// Unit serial number.
  String? birSerial;
  /// Permit To Use number + its validity (free-text date).
  String? ptuNumber;
  String? ptuValidUntil;
  /// Accredited supplier (software) accreditation number.
  String? birAccreditationNo;

  List<Branch> branches;

  List<CustomCategory> customCategories;

  Tenant({
    String? id,
    required this.businessName,
    this.address = '',
    this.currency = 'PHP',
    this.timezone = 'Asia/Manila',
    this.logoUrl,
    this.receiptHeader,
    this.receiptFooter,
    this.receiptAlign = 'center',
    this.receiptTemplate = 1,
    this.ticketTemplate = 1,
    this.printTailLines = 2,
    this.printFont = 'a',
    this.inventoryTrackingEnabled = true,
    this.vatRegistered = false,
    this.tin,
    this.branchCode = '000',
    this.birMin,
    this.birSerial,
    this.ptuNumber,
    this.ptuValidUntil,
    this.birAccreditationNo,
    List<Branch>? branches,
    List<CustomCategory>? customCategories,
  })  : id = id ?? _uuid.v4(),
        branches = branches ?? <Branch>[],
        customCategories = customCategories ?? <CustomCategory>[];
}

class OwnerAccount {
  final String id;
  final String email;
  final String password;
  final String displayName;
  final String tenantId;

  OwnerAccount({
    String? id,
    required this.email,
    required this.password,
    required this.displayName,
    required this.tenantId,
  }) : id = id ?? _uuid.v4();
}
