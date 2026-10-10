# Prestige POS — App Store Submission Reference

Everything needed to submit **Prestige POS** to the Apple App Store. Copy the
relevant sections into App Store Connect.

---

## 1. App Review Information (paste into App Store Connect)

**Sign-In required:** ✅ Yes

| Field | Value |
|---|---|
| **User name** | `appreview@prestigeitsolutions.tech` |
| **Password** | *(leave blank — the app is passwordless)* |

**Notes to reviewer:**

```
This app uses passwordless email login. To sign in:

1. On the welcome screen, tap "Sign in".
2. Enter email: appreview@prestigeitsolutions.tech
3. Tap "Send verification code". (No email is actually sent for this demo account.)
4. Enter the 6-digit code: 246810
5. Enter the owner PIN: 1234

This opens a demo store pre-loaded with products, employees, sales, inventory,
attendance, and payroll so you can test all features.

The app processes in-person payments (cash / GCash / QR) for physical cafe and
retail goods consumed in the real world, so no in-app purchase is used.
```

### Demo credentials (keep private)
| Item | Value |
|---|---|
| Reviewer email | `appreview@prestigeitsolutions.tech` |
| Reviewer code | `246810` |
| Owner PIN | `1234` |
| Demo store | "Prestige Demo Café" (pre-seeded: 14 products, 4 employees, ~45 orders, inventory, attendance, payroll) |

> The demo login works via the `reviewer-login` Supabase Edge Function (the code
> is checked server-side; a wrong code is rejected). It only ever opens the demo
> store — real merchant data is never exposed.

---

## 2. Export Compliance

**App Encryption Documentation** question → choose:
**"None of the algorithms mentioned above"**

The app only uses standard HTTPS/TLS (encryption provided by iOS), so it is
exempt. This is also declared permanently in `ios/Runner/Info.plist`:

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

---

## 3. App Privacy ("nutrition label")

Data the app collects (all used **only** to operate the POS — not for tracking/ads):

| Data | Linked to user | Used for tracking | Purpose |
|---|---|---|---|
| Email address | Yes | No | App functionality (account/login) |
| Name (owner/staff) | Yes | No | App functionality |
| Customer/store business data (products, sales, inventory) | Yes | No | App functionality |
| Coarse/precise Location | Yes | No | App functionality (optional attendance geofence) |

- **We do NOT use data for tracking** (answer "No" to the tracking question).
- **No third-party advertising.**
- Privacy Policy URL: `https://pos.prestigeitsolutions.tech/privacy`

---

## 4. Required capabilities — status

| Requirement | Status | Notes |
|---|---|---|
| Demo reviewer login (for OTP app) | ✅ Done | `reviewer-login` Edge Function + app wiring |
| In-app **Delete Account** (Guideline 5.1.1(v)) | ✅ Done | Settings → Account → Delete account |
| Export compliance | ✅ Done | Info.plist key |
| Location purpose strings | ✅ Done | `NSLocationWhenInUseUsageDescription` etc. |
| Privacy Policy URL | ✅ Live | `https://pos.prestigeitsolutions.tech/privacy` |
| Screenshots (iPad) | ⬜ To do | see §5 |
| Description / keywords / support URL | ✅ Ready | paste-ready copy in §6 |
| Payments = physical goods (no IAP) | ✅ N/A | cash/GCash/QR for real-world goods |

**Before submitting, upload build 9 (`1.0.0+9`)** so the reviewer login, Delete
Account, location strings, the clearer offline/network message, and the Co-owners
list all ship. (Xcode → Archive → Distribute → Upload.)

---

## 5. Screenshots (you capture from the app)

Required for **iPad** (since it's an iPad app). Take on a 12.9"/13" iPad Pro
simulator or device (Apple accepts these for all iPad sizes):

- Sell screen (with the product grid + a cart)
- Dashboard (revenue, orders, top sellers)
- Inventory
- Payroll or Employees
- Receipt / checkout

Sizes: 2048 × 2732 (portrait) or 2732 × 2048 (landscape). 3–10 screenshots.

---

## 6. Store listing content (paste-ready — within Apple's limits)

**App name** (≤30): `Prestige POS`

**Subtitle** (≤30): `POS for cafés & retail`

**Category:** Primary **Business**, Secondary **Finance** (optional)

**Promotional text** (≤170, editable anytime without a new build):
```
Ring up sales, track stock, run shifts and payroll, and print BIR-ready
receipts — all from your iPad. Built for Philippine cafés and shops.
```

**Keywords** (≤100 chars total, comma-separated, no spaces after commas):
```
pos,point of sale,cafe,retail,inventory,bir,receipt,cashier,sari sari,payroll,shift,sales report
```

**Description** (≤4000):
```
Prestige POS is a fast, easy point-of-sale built for Philippine cafés, shops,
and sari-sari stores. Ring up a sale in seconds, take cash or GCash/QR, and hand
over a BIR-ready receipt — all from your iPad.

No complicated setup. Add your products, open a shift, and start selling.

SELLING
• Tap-to-add product grid with categories and quick search
• Cash, GCash, and QR payments, with change calculation
• Hold orders and come back to them later
• Discounts, and BIR-compliant receipts you can print or share

INVENTORY
• Track stock levels and get low-stock alerts
• Stock is deducted automatically as you sell
• Simple product and category management

STAFF & SHIFTS
• Give each staff member a PIN to clock in and ring sales
• Open and close cashier shifts with over/short tracking
• Optional location check-in for attendance

PAYROLL
• Attendance flows straight into payroll
• Daily-rate and hourly computation, overtime, and payslips

DASHBOARD & REPORTS
• See today's revenue, orders, and best sellers at a glance
• Sales reports by date range and payment method
• Co-owners can view the store's sales from the web portal

MADE FOR THE PHILIPPINES
• BIR-ready receipts (TIN, business details, receipt numbering)
• Peso pricing and GCash/QR-friendly checkout

Prestige POS processes in-person payments for real-world goods sold in your café
or shop. There are no in-app purchases.

Questions? Email hello@prestigeitsolutions.tech
```

**Support URL:** `https://pos.prestigeitsolutions.tech`
**Marketing URL (optional):** `https://pos.prestigeitsolutions.tech`
**Privacy Policy URL:** `https://pos.prestigeitsolutions.tech/privacy`
**Copyright:** `© 2026 Prestige IT Solutions`
**Pricing:** Free
**Availability:** Philippines (+ anywhere else you choose)

> Note: the description mentions "no in-app purchases" and that payments are for
> real-world goods — this reinforces the 3.1.1 answer in §1's reviewer notes.

---

## 7. App details

| | |
|---|---|
| Bundle ID | `com.prestigeitsolutions.prestigepos` |
| Team | Chrislyr Phillip Quintila (`96WWFRWS6K`) |
| Backend | Supabase (Postgres + Auth + Edge Functions) |
| Company | Prestige IT Solutions, General Santos City, Philippines |
| Contact | hello@prestigeitsolutions.tech |

---

_Last updated: build 9 (`1.0.0+9`) archived on `android-ios` — same app content
as the never-uploaded build 8 (clearer offline/network message, Co-owners list,
on top of build 7's reviewer login + Delete Account + location strings), bumped
only because a TestFlight build had expired and App Store Connect rejects a
duplicate build number. Listing copy is paste-ready (§6).
Remaining before submit: upload the build 9 archive (Xcode → Organizer →
Distribute; needs an Apple account signed in under Xcode → Settings → Accounts),
capture iPad screenshots (§5), paste the listing, submit for review._
