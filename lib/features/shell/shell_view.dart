import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/responsive.dart';
import 'nav_controller.dart';
import '../bookings/bookings_view.dart';
import '../cart/cart_panel.dart';
import '../dashboard/dashboard_view.dart';
import '../employees/employees_view.dart';
import '../inventory/inventory_view.dart';
import '../maintenance/maintenance_view.dart';
import '../members/members_view.dart';
import '../orders/orders_view.dart';
import '../payroll/payroll_view.dart';
import '../products/products_view.dart';
import '../reports/reports_view.dart';
import '../sell/sell_view.dart';
import '../sessions/sessions_view.dart';
import '../settings/settings_view.dart';
import '../tender/tender_sheet.dart';
import 'floating_bottom_nav.dart';
import 'more_view.dart';
import 'topbar.dart';

class ShellView extends StatefulWidget {
  const ShellView({super.key});

  @override
  State<ShellView> createState() => _ShellViewState();
}

class _ShellViewState extends State<ShellView> {
  /// Guards against double-opening the tender bottom sheet. Without it
  /// every rebuild while [AppState.showTender] is true would schedule a
  /// new post-frame callback and stack another sheet on top — that's
  /// what caused the payment-method picker to re-appear, duplicate
  /// payment rows, the success screen flashing under a fresh form, and
  /// the prior cart leaking into the next order.
  bool _tenderSheetOpen = false;

  @override
  void initState() {
    super.initState();
    // After a sign-in (or lock → pin), the cross-fade ends here. Pop
    // the nav open as part of the welcome — the NavController's
    // collapsed state from the previous session would otherwise leak
    // through and feel cold. Slight delay so the expand animation
    // plays *after* the cross-fade settles instead of fighting it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 180), () {
        if (!mounted) return;
        context.read<NavController>().expand();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    // Open the tender sheet exactly once per "openTender" pulse.
    if (state.showTender && !_tenderSheetOpen) {
      _tenderSheetOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          constraints: const BoxConstraints(maxWidth: double.infinity),
          builder: (_) => const TenderSheet(),
        ).then((_) {
          _tenderSheetOpen = false;
          state.closeTender();
        });
      });
    }

    final navCtrl = context.read<NavController>();
    // While arranging the Sell menu (Customize mode), lock the header + nav so
    // the owner can't wander off mid-arrange — only the Sell surface + the cart
    // panel's "Done editing" stay live.
    final arranging = state.arrangeMode;

    return Scaffold(
      // The on-screen keyboard would normally push the entire body
      // upward. We disable that resize so layouts stay stable; the
      // KeyboardAccessoryField widget already pops a floating card
      // above the keyboard with the label + live preview of what's
      // being typed, so users still see their input even when the
      // underlying field is hidden behind the keyboard.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Full-screen content layer. Any pointer-down or scroll inside this
          // subtree pokes the NavController, which collapses the floating nav
          // down to the compact icon. The nav itself sits OUTSIDE this listener
          // so tapping its tiles doesn't immediately collapse the row.
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => navCtrl.poke(),
            child: NotificationListener<ScrollNotification>(
              onNotification: (_) {
                navCtrl.poke();
                return false;
              },
              child: Column(
                children: [
                  SafeArea(
                    bottom: false,
                    child: IgnorePointer(
                      ignoring: arranging,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: arranging ? 0.45 : 1,
                        child: const TopBar(),
                      ),
                    ),
                  ),
                  Container(height: 0.5, color: YColor.hairline),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: _content(state.selectedRoute)),
                        // Cart only makes sense once a cashier shift is open —
                        // no shift, no taking orders, so hide the panel.
                        if (_showsCart(state.selectedRoute) &&
                            state.hasOpenShift) ...[
                          Container(width: 0.5, color: YColor.hairline),
                          // RepaintBoundary so cart updates (add/remove items)
                          // don't repaint the product grid beside it.
                          SizedBox(
                            width: panelWidth(context,
                                fraction: 0.30, min: 300, max: 360),
                            child: const RepaintBoundary(child: CartPanel()),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Floating glass nav — anchored to bottom edge. Locked while arranging.
          // RepaintBoundary so its expand/collapse animation doesn't repaint
          // the whole content layer behind it.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: RepaintBoundary(
              child: IgnorePointer(
                ignoring: arranging,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: arranging ? 0.45 : 1,
                  child: const FloatingBottomNav(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(AppRoute r) {
    switch (r) {
      case AppRoute.dashboard:
        return const DashboardView();
      case AppRoute.sell:
        return const SellView();
      case AppRoute.bookings:
        return const BookingsView();
      case AppRoute.sessions:
        return const SessionsView();
      case AppRoute.members:
        return const MembersView();
      case AppRoute.orders:
        return const OrdersView();
      case AppRoute.reports:
        return const ReportsView();
      case AppRoute.employees:
        return const EmployeesView();
      case AppRoute.payroll:
        return const PayrollView();
      case AppRoute.products:
        return const ProductsView();
      case AppRoute.inventory:
        return const InventoryView();
      case AppRoute.more:
        return const MoreView();
      case AppRoute.maintenance:
        return const MaintenanceView();
      case AppRoute.settings:
        return const SettingsView();
    }
  }

  bool _showsCart(AppRoute r) => r == AppRoute.sell;
}
