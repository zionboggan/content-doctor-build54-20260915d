/// Receipts for every export, including partially submitted batches.
class RenderJobs {
  final Map<String, Map<String, dynamic>> _jobs = {};
  Iterable<Map<String, dynamic>> get items => _jobs.values;

  /// Only server states that can make progress on their own belong in the
  /// automatic polling loop.  In particular, an `unknown` reply must never
  /// leave the client spinning forever after a server restart or lost receipt.
  Iterable<Map<String, dynamic>> get pending =>
      items.where((job) => ['queued', 'rendering'].contains(job['status']));

  void submitted(
    dynamic result, {
    required String sourceId,
    required String account,
    required String signature,
    String? title,
  }) {
    final id = result is Map ? result['job_id'] : null;
    if (id is! String || id.isEmpty) {
      throw StateError('Export receipt missing. Check status before retrying.');
    }
    _jobs.putIfAbsent(
      id,
      () => {
        'id': id,
        'source_id': sourceId,
        'title': title ?? 'Review export',
        'account': account,
        'signature': signature,
        'status': 'queued',
      },
    );
    update(id, result);
  }

  void update(String id, dynamic result) {
    final job = _jobs[id];
    if (job == null || result is! Map) return;
    final String status = '${result['status'] ?? 'queued'}';
    if (status == 'unknown') {
      job['status'] = 'failed';
      job['error'] =
          'The render service no longer has this receipt. Create a new review export if needed.';
      job['review_id'] = null;
      return;
    }
    if (status == 'ready_for_review') {
      final dynamic asset = result['asset'];
      final dynamic reviewId = asset is Map ? asset['id'] : null;
      if (reviewId == null || '$reviewId'.isEmpty) {
        job['status'] = 'failed';
        job['error'] =
            'The render finished without a review asset. Create a new review export if needed.';
        job['review_id'] = null;
        return;
      }
      job['status'] = status;
      job['error'] = null;
      job['review_id'] = '$reviewId';
      return;
    }
    job['status'] = status;
    job['error'] = result['error'];
    job['review_id'] = null;
  }

  List<Map<String, dynamic>> toJson() => items.toList();
  void restore(dynamic rows) {
    if (rows is! List) return;
    for (final row in rows) {
      if (row is Map && row['id'] is String && row['account'] is String) {
        _jobs[row['id']] = Map<String, dynamic>.from(row);
      }
    }
  }
}
