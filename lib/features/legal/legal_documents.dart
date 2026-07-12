/// Plain-data definitions of the Terms & Conditions and Privacy Policy that
/// ship with Prestige Café. Rendered by [LegalDocumentView].
///
/// IMPORTANT: These are starter templates suitable for development. Before
/// going to production you should:
///   • Have a licensed lawyer review and adapt them to your jurisdiction.
///   • Update [_effectiveDate] when terms change materially.
///   • Update [_contactEmail] / [_companyAddress] to your real legal entity.
library;

const _effectiveDate = '2026-05-20';
const _companyLegalName = 'Prestige IT Solutions';
const _productName = 'Prestige Café';
const _contactEmail = 'hello@prestigeitsolutions.tech';
const _contactSupportEmail = 'hello@prestigeitsolutions.tech';
const _companyAddress =
    'Prestige IT Solutions, General Santos City, Philippines';
const _governingLawJurisdiction = 'Republic of the Philippines';
const _venueCity = 'General Santos City';

/// A heading + paragraphs block inside a legal document.
class LegalSection {
  final String heading;
  final List<String> paragraphs;
  const LegalSection({required this.heading, required this.paragraphs});
}

class LegalDocument {
  final String title;
  final String shortName;
  final String effectiveDate;
  final String intro;
  final List<LegalSection> sections;
  final String contactNote;

  const LegalDocument({
    required this.title,
    required this.shortName,
    required this.effectiveDate,
    required this.intro,
    required this.sections,
    required this.contactNote,
  });
}

// ───── TERMS & CONDITIONS ─────

const LegalDocument termsAndConditions = LegalDocument(
  title: 'Terms & Conditions',
  shortName: 'Terms',
  effectiveDate: _effectiveDate,
  intro:
      'Welcome to $_productName. These Terms & Conditions ("Terms") form a '
      'binding agreement between you and $_companyLegalName ("we", "our", or '
      '"Prestige") and govern your access to and use of the $_productName '
      'mobile and tablet application and related services (collectively, the '
      '"Service"). By creating an account or using the Service, you agree to '
      'these Terms. If you do not agree, do not use the Service.',
  sections: [
    LegalSection(
      heading: '1. Eligibility & account registration',
      paragraphs: [
        'You must be at least 18 years old and legally able to enter into a '
        'binding contract to use the Service. By registering you confirm that '
        'the information you provide is accurate and that you are authorized '
        'to bind the business on whose behalf you register.',
        'You are responsible for safeguarding access to your account, '
        'including the email address used for one-time codes and the PIN '
        'codes you assign to your staff. Notify us promptly at '
        '$_contactSupportEmail if you suspect unauthorized access.',
      ],
    ),
    LegalSection(
      heading: '2. Description of the Service',
      paragraphs: [
        '$_productName is a multi-tenant point-of-sale platform for cafés, '
        'food and beverage outlets, and similar small retail businesses. '
        'Features include product cataloguing, sales ringing, inventory '
        'tracking, employee management, payroll computation, and reporting.',
        'We may update, add, modify, or remove features from time to time. '
        'We will make reasonable efforts to notify you of material changes '
        'in advance.',
      ],
    ),
    LegalSection(
      heading: '3. Subscription, billing, and fees',
      paragraphs: [
        'Pricing, billing cycles, and applicable taxes will be communicated '
        'before any paid subscription begins. Unless stated otherwise, fees '
        'are charged in Philippine Pesos (PHP) and are non-refundable except '
        'where required by law.',
        'You authorize us to charge the payment method on file for all fees '
        'and applicable taxes. Failure to pay may result in suspension or '
        'termination of your account after reasonable notice.',
      ],
    ),
    LegalSection(
      heading: '4. Your data',
      paragraphs: [
        'You retain ownership of all data you upload to the Service, '
        'including business details, menus, recipes, inventory counts, '
        'employee records, customer information, and sales history '
        '(collectively, "Customer Data"). We act as a data processor with '
        'respect to Customer Data.',
        'You grant us a limited, worldwide, non-exclusive licence to host, '
        'transmit, and display Customer Data solely as necessary to provide '
        'the Service to you. We will not sell your Customer Data and will '
        'only access it where strictly required to operate, support, or '
        'improve the Service, or where required by law.',
        'You are responsible for ensuring that you have all necessary '
        'consents from your employees and customers before entering their '
        'personal information into the Service, in compliance with the '
        'Philippine Data Privacy Act of 2012 (Republic Act No. 10173) and '
        'any applicable regulations.',
      ],
    ),
    LegalSection(
      heading: '5. Acceptable use',
      paragraphs: [
        'You agree not to: (a) use the Service for any unlawful purpose; '
        '(b) interfere with or disrupt the Service or its infrastructure; '
        '(c) attempt to gain unauthorized access to other accounts or our '
        'systems; (d) reverse engineer, decompile, or attempt to extract '
        'the source code of the Service except as permitted by law; '
        '(e) resell, sublicense, or commercially exploit the Service '
        'without our written consent.',
      ],
    ),
    LegalSection(
      heading: '6. Intellectual property',
      paragraphs: [
        'The Service, including its software, designs, trademarks, and '
        'documentation, is owned by $_companyLegalName or its licensors and '
        'is protected by intellectual property laws. Nothing in these Terms '
        'transfers any ownership in the Service to you.',
        'Feedback you provide is appreciated and may be used by us without '
        'restriction or obligation.',
      ],
    ),
    LegalSection(
      heading: '7. Third-party services',
      paragraphs: [
        'The Service uses Supabase (operated by Supabase Inc.) for '
        'authentication and data storage, and may integrate with payment '
        'processors, courier services, or other third parties to deliver '
        'specific features. Your use of those services is also governed by '
        'their respective terms of service. We do not control, and are not '
        'responsible for, the practices of third-party providers.',
      ],
    ),
    LegalSection(
      heading: '8. Service availability and support',
      paragraphs: [
        'We aim to make the Service available continuously but do not '
        'guarantee uninterrupted access. Planned maintenance windows will '
        'be communicated where practical. The Service is provided "as is" '
        'and "as available" without warranties of any kind, whether '
        'express, implied, or statutory, except as required by law.',
      ],
    ),
    LegalSection(
      heading: '9. Termination',
      paragraphs: [
        'You may stop using the Service and delete your account at any time '
        'from within the app. We may suspend or terminate your access if '
        'you materially breach these Terms, if required by law, or if your '
        'continued use poses a security risk.',
        'Upon termination, you may export your Customer Data within thirty '
        '(30) days; after that period we may permanently delete it. Sections '
        'that by their nature should survive termination (including '
        'ownership, indemnification, and limitations of liability) will '
        'remain in effect.',
      ],
    ),
    LegalSection(
      heading: '10. Indemnification',
      paragraphs: [
        'You agree to indemnify and hold $_companyLegalName, its officers, '
        'employees, and agents harmless from any claim, demand, loss, '
        'liability, or expense (including reasonable lawyer\'s fees) arising '
        'from your use of the Service, your Customer Data, or your '
        'violation of these Terms.',
      ],
    ),
    LegalSection(
      heading: '11. Limitation of liability',
      paragraphs: [
        'To the maximum extent permitted by law, $_companyLegalName will '
        'not be liable for any indirect, incidental, special, consequential, '
        'or punitive damages, or any loss of profits, revenue, goodwill, '
        'data, or business opportunities, even if we have been advised of '
        'the possibility of such damages.',
        'Our aggregate liability arising out of or in connection with these '
        'Terms or the Service will not exceed the amounts actually paid by '
        'you to us in the twelve (12) months preceding the event giving '
        'rise to the claim.',
      ],
    ),
    LegalSection(
      heading: '12. Changes to these Terms',
      paragraphs: [
        'We may update these Terms from time to time. If we make a material '
        'change we will notify you at least thirty (30) days before it takes '
        'effect, via in-app notice or to the email address on file. Your '
        'continued use of the Service after the effective date constitutes '
        'acceptance of the updated Terms.',
      ],
    ),
    LegalSection(
      heading: '13. Governing law and dispute resolution',
      paragraphs: [
        'These Terms are governed by the laws of the $_governingLawJurisdiction, '
        'without regard to conflict-of-laws principles. Any dispute will '
        'first be resolved in good faith between the parties. If unresolved, '
        'disputes will be brought before the competent courts of '
        '$_venueCity.',
      ],
    ),
  ],
  contactNote:
      'Questions about these Terms? Email $_contactEmail or write to '
      '$_companyAddress.',
);

// ───── PRIVACY POLICY ─────

const LegalDocument privacyPolicy = LegalDocument(
  title: 'Privacy Policy',
  shortName: 'Privacy Policy',
  effectiveDate: _effectiveDate,
  intro:
      'This Privacy Policy explains how $_companyLegalName ("we", "our", or '
      '"Prestige") collects, uses, and protects personal information when you '
      'use $_productName (the "Service"). We are committed to processing your '
      'data in accordance with the Philippine Data Privacy Act of 2012 '
      '(Republic Act No. 10173) and applicable international standards.',
  sections: [
    LegalSection(
      heading: '1. Information we collect',
      paragraphs: [
        'Account information — when you register, we collect your name and '
        'email address. We do not store passwords; sign-in uses one-time '
        'codes sent to your email.',
        'Business information — the business name, address, branches, and '
        'currency you configure during onboarding.',
        'Catalog and operational data — products, recipes, ingredients, '
        'pricing, modifier groups, add-ons, inventory levels, payroll rules, '
        'and leave types you create.',
        'Employee data — names, roles, contact information, payroll details, '
        'hours worked, and timesheets you enter. You are responsible for '
        'collecting employee consent before entering their information.',
        'Customer data — if you choose to record customers (e.g., for '
        'membership/loyalty), the contact information you enter.',
        'Sales data — transactions, payments, receipts, and other activity '
        'generated through use of the Service.',
        'Device and usage information — operating system, app version, '
        'crash reports, performance metrics, and similar diagnostics needed '
        'to operate and improve the Service.',
      ],
    ),
    LegalSection(
      heading: '2. How we use information',
      paragraphs: [
        'We use personal information to: (a) authenticate you and your '
        'staff; (b) provide the features of the Service; (c) deliver receipts '
        'and email notifications; (d) provide customer support; '
        '(e) detect, prevent, and address fraud, abuse, or security issues; '
        '(f) comply with legal obligations.',
        'We do not sell your personal information or share it with third '
        'parties for their own advertising.',
      ],
    ),
    LegalSection(
      heading: '3. Legal basis for processing',
      paragraphs: [
        'We process your information based on (a) your consent, given when '
        'you accept these terms and the Privacy Policy; (b) the necessity '
        'of performing the contract under which the Service is provided to '
        'you; (c) our legitimate interests in keeping the Service secure '
        'and improving its quality; and (d) compliance with legal '
        'obligations.',
      ],
    ),
    LegalSection(
      heading: '4. How we share information',
      paragraphs: [
        'Service providers — we use Supabase Inc. as our authentication and '
        'database host. Supabase processes data on our behalf under a Data '
        'Processing Agreement and applies industry-standard encryption in '
        'transit and at rest.',
        'Legal compliance — we may disclose information if required by a '
        'valid legal request from competent authorities, or where necessary '
        'to protect the rights, property, or safety of Prestige, our users, '
        'or the public.',
        'Business transfers — if Prestige is involved in a merger, '
        'acquisition, or sale of assets, your information may be transferred. '
        'We will notify you and your continued use after such transfer is '
        'subject to the same privacy commitments.',
      ],
    ),
    LegalSection(
      heading: '5. International data transfers',
      paragraphs: [
        'Supabase processes data in regional data centres which may be '
        'located outside the Philippines. Where data is transferred '
        'internationally we rely on contractual safeguards, including the '
        'standard contractual clauses, to ensure your information is '
        'protected at a comparable level.',
      ],
    ),
    LegalSection(
      heading: '6. Data security',
      paragraphs: [
        'We apply industry-standard safeguards to protect your information, '
        'including TLS encryption in transit, encryption at rest, '
        'OAuth-grade authentication tokens stored in the device\'s secure '
        'enclave (Keychain on iOS, Keystore on Android), and Row Level '
        'Security policies on our database. No system is perfectly secure, '
        'and we cannot guarantee absolute protection; you can help by '
        'choosing strong staff PINs and signing out on shared devices.',
      ],
    ),
    LegalSection(
      heading: '7. Data retention',
      paragraphs: [
        'We retain your information for as long as your account is active. '
        'If you delete your account, we will delete your Customer Data '
        'within thirty (30) days, except where longer retention is required '
        'by law (for example, tax or accounting records you have generated '
        'through the Service).',
        'Backups and disaster-recovery copies may persist for up to ninety '
        '(90) days following deletion before they are overwritten.',
      ],
    ),
    LegalSection(
      heading: '8. Your rights',
      paragraphs: [
        'Under the Philippine Data Privacy Act and similar laws, you have '
        'the right to: (a) be informed about how your personal data is '
        'processed; (b) access the information we hold about you; '
        '(c) request correction of inaccurate information; (d) request '
        'erasure or blocking of your data; (e) data portability — receive '
        'a copy of your Customer Data in a structured format; '
        '(f) withdraw consent at any time; (g) lodge a complaint with the '
        'National Privacy Commission.',
        'To exercise these rights, contact us at $_contactEmail. We will '
        'respond within thirty (30) days.',
      ],
    ),
    LegalSection(
      heading: '9. Children\'s privacy',
      paragraphs: [
        'The Service is intended for business owners and their authorized '
        'staff. We do not knowingly collect personal information from '
        'individuals under 18. If you become aware that a minor has '
        'provided personal information, contact us so we can delete it.',
      ],
    ),
    LegalSection(
      heading: '10. Cookies and similar technologies',
      paragraphs: [
        'The mobile app does not use browser cookies. Where we offer a '
        'web dashboard, it uses essential cookies only — for authentication '
        'and to remember your preferences. No third-party advertising '
        'trackers are used.',
      ],
    ),
    LegalSection(
      heading: '11. Changes to this Privacy Policy',
      paragraphs: [
        'We may update this Privacy Policy from time to time. If we make a '
        'material change, we will notify you at least thirty (30) days '
        'before it takes effect, via in-app notice or to the email address '
        'on file. The "effective date" at the top of this document is '
        'updated whenever we publish changes.',
      ],
    ),
  ],
  contactNote:
      'Privacy questions or requests? Email our Data Protection Officer at '
      '$_contactEmail. Postal: $_companyAddress.',
);
