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
3. Tap Continue. (No email is sent for this demo account.)
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
- Privacy Policy URL: `https://prestigeitsolutions.tech/privacy`

---

## 4. Required capabilities — status

| Requirement | Status | Notes |
|---|---|---|
| Demo reviewer login (for OTP app) | ✅ Done | `reviewer-login` Edge Function + app wiring |
| In-app **Delete Account** (Guideline 5.1.1(v)) | ✅ Done | Settings → Account → Delete account |
| Export compliance | ✅ Done | Info.plist key |
| Location purpose strings | ✅ Done | `NSLocationWhenInUseUsageDescription` etc. |
| Privacy Policy URL | 🟡 Deploy | website repo → Vercel → prestigeitsolutions.tech |
| Screenshots (iPad) | ⬜ To do | see §5 |
| Description / keywords / support URL | ⬜ To do | see §6 |
| Payments = physical goods (no IAP) | ✅ N/A | cash/GCash/QR for real-world goods |

**Before submitting, upload a NEW build** (build 7+) so the reviewer login,
Delete Account, and location strings are included.

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

## 6. Store listing content

- **App name:** Prestige POS
- **Subtitle:** e.g. "POS for cafés & retail"
- **Category:** Business
- **Description:** fast, BIR-ready point-of-sale — selling, inventory, shifts,
  payroll, receipts, and reports on your iPad. (Expand from the website copy.)
- **Keywords:** pos, point of sale, cafe, retail, inventory, bir, receipt, cashier
- **Support URL:** `https://prestigeitsolutions.tech`
- **Marketing URL (optional):** `https://prestigeitsolutions.tech`
- **Pricing:** Free
- **Availability:** Philippines (+ anywhere else you choose)

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

_Last updated: build 6 shipped; reviewer login + Delete Account committed on
`android-ios` (pending build 7)._
