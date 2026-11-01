import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hasad_erp_v2/design/hasad_components.dart';
import 'package:hasad_erp_v2/design/hasad_theme.dart';
import 'package:hasad_erp_v2/sales/dev/s3_posting_smoke_contract.dart';
import 'package:hasad_erp_v2/sales/dev/s3_posting_smoke_service.dart';

/// DEV-only, one-time diagnostic for the owner-authorized S3 posting.
///
/// Reached only when the app is built with
/// `--dart-define=ENABLE_S3_POSTING_SMOKE=true` and the configured Supabase
/// project is the authorized DEV project. The general production posting
/// button stays disabled; this screen never changes [SalesRepository] flags.
class S3PostingSmokeScreen extends StatefulWidget {
  const S3PostingSmokeScreen({
    super.key,
    required this.selectedCompanyId,
    this.gateway,
    this.now,
  });

  final String selectedCompanyId;
  final S3PostingSmokeGateway? gateway;
  final DateTime Function()? now;

  @override
  State<S3PostingSmokeScreen> createState() => _S3PostingSmokeScreenState();
}

class _S3PostingSmokeScreenState extends State<S3PostingSmokeScreen> {
  late final S3PostingSmokeController _controller;
  Timer? _freshnessTimer;

  @override
  void initState() {
    super.initState();
    _controller = S3PostingSmokeController(
      widget.gateway ?? SupabaseS3PostingSmokeGateway(),
      selectedCompanyId: widget.selectedCompanyId,
      now: widget.now,
    );
    // The precheck has a short validity window; refresh the button state so a
    // stale report cannot be posted with an outdated label. A test clock is
    // deterministic, so no timer is started when one is injected.
    if (widget.now == null) {
      _freshnessTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _freshnessTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirmAndPost() async {
    final target = _controller.report?.target;
    if (target == null || !_controller.canPost) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _ConfirmPostingDialog(target: target),
    );
    if (confirmed == true && mounted) {
      await _controller.postOnce();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HasadPageHeader(
            title: 'تشخيص DEV — ترحيل S3 لمرة واحدة',
            subtitle:
                'شاشة تشخيصية لمرة واحدة خارج نطاق الإنتاج. لا تُفعّل زر الترحيل '
                'العام ولا تُعيد المحاولة تلقائياً.',
            trailing: HasadStatusBadge(
              label: 'DEV فقط',
              color: _controller.activeProjectRef ==
                      S3PostingSmokeContract.projectRef
                  ? HasadPalette.warning
                  : HasadPalette.danger,
            ),
          ),
          const SizedBox(height: 18),
          _projectBanner(context),
          const SizedBox(height: 18),
          _targetCard(context),
          const SizedBox(height: 18),
          _precheckCard(context),
          const SizedBox(height: 18),
          if (_controller.report case final report?) ...[
            _checksCard(context, report),
            const SizedBox(height: 18),
            if (report.target case final target?) ...[
              _effectsCard(context, target),
              const SizedBox(height: 18),
            ],
          ],
          if (_controller.failure case final failure?) ...[
            _failureCard(context, failure),
            const SizedBox(height: 18),
          ],
          if (_controller.outcome case final outcome?) ...[
            _outcomeCard(context, outcome),
            const SizedBox(height: 18),
          ],
          _postingCard(context),
        ],
      ),
    );
  }

  Widget _projectBanner(BuildContext context) {
    final active = _controller.activeProjectRef;
    final matches = active == S3PostingSmokeContract.projectRef;
    final color = matches ? HasadPalette.warning : HasadPalette.danger;
    return HasadCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.science_outlined, color: color, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  matches
                      ? 'المشروع النشط مطابق لمشروع DEV المصرح به'
                      : 'المشروع النشط لا يطابق مشروع DEV المصرح به — الترحيل محظور',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800, color: color),
                ),
                const SizedBox(height: 6),
                const Text(
                  'يتحقق التطبيق من عنوان PostgREST الفعلي للعميل المهيأ، وليس من '
                  'متغير بيئة منفصل. أي مشروع آخر يوقف كل القراءات والترحيل.',
                  style: TextStyle(color: HasadPalette.muted),
                ),
                const SizedBox(height: 10),
                _KeyValue(
                  label: 'المشروع النشط',
                  value: active ?? 'غير معروف',
                  selectable: true,
                ),
                _KeyValue(
                  label: 'المشروع المصرح به',
                  value: S3PostingSmokeContract.projectRef,
                  selectable: true,
                ),
                _KeyValue(
                  label: 'المستخدم الحالي',
                  value:
                      _controller.currentUserEmail ??
                      _controller.currentUserId ??
                      'لا توجد جلسة',
                  selectable: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _targetCard(BuildContext context) => HasadCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'الهدف المصرح به — قيمة ثابتة لا تُدخل يدوياً',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        _KeyValue(
          label: 'معرّف الشركة',
          value: S3PostingSmokeContract.companyId,
          selectable: true,
        ),
        _KeyValue(
          label: 'معرّف الفاتورة',
          value: S3PostingSmokeContract.documentId,
          selectable: true,
        ),
        _KeyValue(
          label: 'مفتاح التكرار',
          value: S3PostingSmokeContract.idempotencyKey,
          selectable: true,
        ),
        _KeyValue(label: 'تاريخ الفاتورة', value: S3PostingSmokeContract.docDate),
        _KeyValue(
          label: 'الإجمالي / الضريبة',
          value: '10.00 / 0.00',
        ),
        const SizedBox(height: 8),
        const Text(
          'تُمرّر هذه القيم الثلاث فقط إلى hasad.post_sales_invoice: '
          'p_company_id و p_document_id و p_idempotency_key.',
          style: TextStyle(color: HasadPalette.muted),
        ),
      ],
    ),
  );

  Widget _precheckCard(BuildContext context) => HasadCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '1) فحص القراءة فقط الآن',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'شغّل أولاً ملف الفحص المعتمد على DEV:\n'
          'security/candidates/s3_posting_smoke_precheck_readonly.sql\n'
          'وتأكد أن صف هذه الفاتورة يحمل '
          'READY_FOR_ZERO_TAX_POSTING_TEST. الفحص أدناه يعيد قراءة الهوية '
          'والمبالغ والمخزون والصلاحية من نفس الجلسة، لكنه لا يستبدل فحص SQL '
          'في حقول الخادم غير القابلة للقراءة من التطبيق (فترة مفتوحة، خرائط '
          'حسابات، عدّادات أرقام).',
          style: TextStyle(color: HasadPalette.muted),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            FilledButton.icon(
              key: const ValueKey('s3-smoke-precheck'),
              onPressed: _controller.canRunPrecheck
                  ? _controller.runPrecheck
                  : null,
              icon: _controller.runningPrecheck
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fact_check_outlined),
              label: Text(
                _controller.runningPrecheck
                    ? 'جارٍ الفحص...'
                    : 'تشغيل فحص القراءة فقط',
              ),
            ),
            if (_controller.report case final report?) ...[
              const SizedBox(width: 14),
              HasadStatusBadge(
                label: report.passed
                    ? S3PostingSmokeContract.expectedPrecheckVerdict
                    : 'BLOCKED',
                color: report.passed
                    ? HasadPalette.success
                    : HasadPalette.danger,
              ),
            ],
          ],
        ),
        if (_controller.report == null)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'لم يُشغّل الفحص بعد.',
              style: TextStyle(color: HasadPalette.muted),
            ),
          )
        else if (!_controller.isPrecheckFresh && !_controller.attempted)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'انتهت صلاحية الفحص الآلي (10 دقائق). أعد تشغيل فحص القراءة '
              'فقط قبل أي محاولة.',
              style: TextStyle(
                color: HasadPalette.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _checksCard(BuildContext context, S3PrecheckReport report) => HasadCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'نتيجة الفحص الآلي',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        for (final check in report.checks)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  check.passed ? Icons.check_circle : Icons.cancel,
                  color: check.passed
                      ? HasadPalette.success
                      : HasadPalette.danger,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        check.label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        check.detail,
                        style: const TextStyle(
                          color: HasadPalette.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _effectsCard(BuildContext context, S3SmokeTarget target) => HasadCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '2) الأثر المتوقع في قاعدة البيانات',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        _KeyValue(
          label: 'مدين الذمم المدينة (AR)',
          value: '${target.gross} (إجمالي الفاتورة)',
        ),
        _KeyValue(
          label: 'دائن إيرادات المبيعات',
          value: '${target.net} (بدون سطر ضريبة)',
        ),
        _KeyValue(
          label: 'ضريبة القيمة المضافة',
          value: '0.00 — لا يُكتب أي سطر ضريبة',
        ),
        _KeyValue(
          label: 'مدين تكلفة المبيعات (COGS)',
          value: target.cogs,
        ),
        _KeyValue(
          label: 'دائن مراقبة المخزون',
          value: target.cogs,
        ),
        _KeyValue(
          label: 'حركات المخزون',
          value: '${target.stockedLineCount} حركة sales_issue (خروج)',
        ),
        _KeyValue(
          label: 'عدد أسطر القيد',
          value: '${target.journalLineCount}',
        ),
        _KeyValue(
          label: 'الأرقام الرسمية',
          value: 'SI-2026-#### و JE-2026-#### — القيم الدقيقة من فحص SQL',
        ),
        const SizedBox(height: 8),
        if (target.cogsCents == 0)
          const Text(
            'تنبيه: التكلفة المتوقعة 0.00. وفق العقد الحالي لن يُكتب سطر COGS '
            'ولا سطر مخزون، وستكون ربط حركة المخزون بسطر القيد فارغاً. هذه فجوة '
            'سلامة معروفة وليست إذناً بتجاوزها.',
            style: TextStyle(color: HasadPalette.warning),
          )
        else
          const Text(
            'تُحسب التكلفة من متوسط التكلفة المرجّح المقروء الآن، وقد تتغير قبل '
            'الترحيل. الخادم هو المرجع النهائي.',
            style: TextStyle(color: HasadPalette.muted),
          ),
        const SizedBox(height: 10),
        for (final line in target.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'بند ${line.lineNo}: كمية ${line.quantity} — '
              '${line.tracked ? 'مخزني، تكلفة الوحدة ${line.unitCost ?? '?'}، COGS ${line.cogs}' : 'غير مخزني، بلا حركة مخزون'}',
              style: const TextStyle(
                color: HasadPalette.muted,
                fontSize: 12,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _failureCard(BuildContext context, S3SmokeFailure failure) {
    final color = failure.outcomeUncertain
        ? HasadPalette.danger
        : HasadPalette.warning;
    return HasadCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                failure.outcomeUncertain
                    ? Icons.report_gmailerrorred
                    : Icons.error_outline,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  failure.outcomeUncertain
                      ? 'نتيجة غير مؤكدة — أوقف المحاولات'
                      : 'لم يُعتبر الترحيل ناجحاً',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(failure.message),
          const SizedBox(height: 6),
          Text(
            'الرمز: ${failure.code}',
            style: const TextStyle(color: HasadPalette.muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          const Text(
            'لا توجد إعادة محاولة من هذه الشاشة. شغّل فحص ما بعد الترحيل '
            '(s3_posting_smoke_postverify_readonly.sql) بعد استبدال UUID الفاتورة '
            'أدناه، ثم قرر.',
            style: TextStyle(color: HasadPalette.muted),
          ),
          const SizedBox(height: 4),
          SelectableText(
            S3PostingSmokeContract.documentId,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _outcomeCard(BuildContext context, S3PostingOutcome outcome) =>
      HasadCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified, color: HasadPalette.success),
                const SizedBox(width: 8),
                Text(
                  outcome.replayed
                      ? 'أعاد الخادم نتيجة ترحيل سابقة'
                      : 'تم الترحيل مرة واحدة وأعاد الخادم التأكيد',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: HasadPalette.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _KeyValue(
              label: 'رقم الفاتورة الرسمي',
              value: outcome.documentNo,
              selectable: true,
            ),
            _KeyValue(
              label: 'رقم القيد اليومي',
              value: outcome.journalEntryNo,
              selectable: true,
            ),
            const SizedBox(height: 8),
            const Text(
              'الخطوة التالية إلزامية: شغّل فحص ما بعد الترحيل للتحقق من القيد '
              'والمخزون والأرقام. لا تُعِد الترحيل من هذه الشاشة.',
              style: TextStyle(color: HasadPalette.muted),
            ),
          ],
        ),
      );

  Widget _postingCard(BuildContext context) {
    final locked = _controller.attempted || _controller.outcome != null;
    return HasadCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '3) التأكيد والتنفيذ الوحيد',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          CheckboxListTile(
            key: const ValueKey('s3-smoke-attestation'),
            value: _controller.attestation,
            onChanged: _controller.canAttest
                ? (value) => _controller.setAttestation(value ?? false)
                : null,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'أقر أنني شغّلت فحص SQL للقراءة فقط على DEV قبل هذه اللحظة، '
              'وكان صف هذه الفاتورة بالضبط '
              'READY_FOR_ZERO_TAX_POSTING_TEST.',
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'زر الترحيل يفتح نافذة تأكيد أخيرة تعرض المعرّفات والأثر المتوقع. '
            'بعد الضغط على زر التنفيذ داخل النافذة تُستهلك المحاولة الوحيدة ولا '
            'توجد إعادة محاولة تلقائية أو يدوية من هذه الشاشة.',
            style: TextStyle(color: HasadPalette.muted),
          ),
          if (locked) ...[
            const SizedBox(height: 8),
            Text(
              _controller.outcome != null
                  ? 'تم استخدام المحاولة الوحيدة بنجاح. شغّل فحص ما بعد الترحيل.'
                  : 'تم استخدام المحاولة الوحيدة. لا يوجد زر تنفيذ آخر. شغّل '
                        'فحص ما بعد الترحيل قبل أي قرار.',
              style: const TextStyle(
                color: HasadPalette.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('s3-smoke-post'),
            onPressed: _controller.canPost ? _confirmAndPost : null,
            icon: _controller.posting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.warning_amber_rounded),
            label: Text(
              _controller.posting
                  ? 'جارٍ الترحيل الوحيد...'
                  : locked
                  ? 'تم استهلاك المحاولة الوحيدة'
                  : 'فتح تأكيد الترحيل الوحيد',
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmPostingDialog extends StatelessWidget {
  const _ConfirmPostingDialog({required this.target});

  final S3SmokeTarget target;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Row(
      children: [
        Icon(Icons.warning_amber_rounded, color: HasadPalette.danger),
        SizedBox(width: 8),
        Expanded(child: Text('تأكيد الترحيل الوحيد على DEV')),
      ],
    ),
    content: SizedBox(
      width: 720,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'سيُستدعى hasad.post_sales_invoice مرة واحدة بالمعرّفات التالية. '
              'لا يمكن التراجع عن الترحيل من الواجهة، وأي خطأ أو مهلة لا يُعيد '
              'المحاولة تلقائياً.',
              style: TextStyle(color: HasadPalette.muted),
            ),
            const SizedBox(height: 14),
            _KeyValue(label: 'الشركة', value: target.companyName),
            _KeyValue(
              label: 'معرّف الشركة',
              value: target.companyId,
              selectable: true,
            ),
            _KeyValue(
              label: 'معرّف الفاتورة',
              value: target.invoiceId,
              selectable: true,
            ),
            _KeyValue(
              label: 'مفتاح التكرار',
              value: target.idempotencyKey,
              selectable: true,
            ),
            _KeyValue(label: 'التاريخ', value: target.docDate),
            _KeyValue(
              label: 'الصافي / الضريبة / الإجمالي',
              value: '${target.net} / ${target.tax} / ${target.gross}',
            ),
            const Divider(height: 24),
            const Text(
              'الأثر المتوقع:',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            _KeyValue(label: 'مدين AR', value: target.gross),
            _KeyValue(label: 'دائن الإيراد', value: target.net),
            _KeyValue(label: 'ضريبة', value: '0.00 (لا سطر)'),
            _KeyValue(label: 'مدين COGS', value: target.cogs),
            _KeyValue(label: 'دائن المخزون', value: target.cogs),
            _KeyValue(
              label: 'حركات sales_issue',
              value: '${target.stockedLineCount}',
            ),
            _KeyValue(
              label: 'أسطر القيد',
              value: '${target.journalLineCount}',
            ),
            _KeyValue(
              label: 'الأرقام',
              value: 'SI-2026-#### / JE-2026-####',
            ),
            if (target.cogsCents == 0) ...[
              const SizedBox(height: 8),
              const Text(
                'تنبيه: COGS المتوقع 0.00، لذا لن تُكتب أسطر COGS/المخزون '
                'ولن تُربط حركة المخزون بسطر قيد.',
                style: TextStyle(
                  color: HasadPalette.warning,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        key: const ValueKey('s3-smoke-post-cancel'),
        onPressed: () => Navigator.pop(context, false),
        child: const Text('إلغاء'),
      ),
      FilledButton.icon(
        key: const ValueKey('s3-smoke-post-confirm'),
        onPressed: () => Navigator.pop(context, true),
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('تنفيذ الترحيل الوحيد'),
      ),
    ],
  );
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 190,
          child: Text(
            label,
            style: const TextStyle(
              color: HasadPalette.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: selectable
              ? SelectableText(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                )
              : Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
        ),
      ],
    ),
  );
}
