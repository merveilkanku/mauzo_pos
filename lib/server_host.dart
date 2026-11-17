import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

// Types d'opérations que les caisses Mauzo POS savent échanger.
const _allowedTypes = {
  'product', 'stock', 'reception', 'sale', 'refund', 'session', 'closure', 'caisse', 'user',
  'customer', 'cust_delta', 'sale_customer', 'settings', 'expense', 'audit', 'misc',
};

class Device {
  Device(this.id, this.name, this.lastSeen);
  final String id;
  String name;
  DateTime lastSeen;
  bool get online => DateTime.now().difference(lastSeen).inSeconds < 90;
}

class _R {
  _R(this.code, this.text);
  final int code;
  final String text;
}

/// Serveur Mauzo : un journal d'opérations commun. Chaque caisse y dépose ses opérations (POST /sync)
/// et récupère celles des autres (GET /feed). Le journal est écrit sur disque ligne par ligne.
class MauzoServer extends ChangeNotifier {
  late final Directory dir;
  HttpServer? _http;
  String key = '';
  int port = 8080;
  bool autoStart = false;
  DateTime? lastBackup;
  final List<Map<String, dynamic>> _ops = [];
  final Set<String> _ids = {};
  final Map<String, Device> devices = {};
  final Map<String, int> counts = {};
  final List<String> logs = [];

  bool get running => _http != null;
  int get opCount => _ops.length;
  String get path => dir.path;
  int get onlineCount => devices.values.where((d) => d.online).length;
  String get sep => Platform.pathSeparator;
  File get _opsFile => File('${dir.path}${sep}ops.jsonl');
  File get _cfgFile => File('${dir.path}${sep}config.json');

  void _log(String t) {
    final n = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    logs.insert(0, '${two(n.hour)}:${two(n.minute)}:${two(n.second)}  $t');
    if (logs.length > 300) logs.removeLast();
    notifyListeners();
  }

  String _newKey() {
    final r = Random.secure();
    return 'mz_${base64Url.encode(List<int>.generate(18, (_) => r.nextInt(256))).replaceAll('=', '')}';
  }

  void _count(String type) => counts[type] = (counts[type] ?? 0) + 1;

  Future<void> load() async {
    final base = Platform.environment['APPDATA'] ?? Platform.environment['HOME'] ?? Directory.current.path;
    dir = Directory('$base${Platform.pathSeparator}MauzoServeur');
    await dir.create(recursive: true);
    if (await _cfgFile.exists()) {
      try {
        final j = jsonDecode(await _cfgFile.readAsString()) as Map<String, dynamic>;
        key = (j['key'] as String?) ?? '';
        port = (j['port'] as int?) ?? 8080;
        autoStart = (j['autoStart'] as bool?) ?? false;
      } catch (_) {}
    }
    if (key.isEmpty) {
      key = _newKey();
      await saveConfig();
    }
    if (await _opsFile.exists()) {
      var i = 0;
      for (final line in await _opsFile.readAsLines()) {
        if (line.trim().isEmpty) continue;
        i++;
        try {
          final m = jsonDecode(line) as Map<String, dynamic>;
          _ops.add(m);
          _ids.add(m['id'] as String);
          _count(m['type'] as String);
        } catch (_) {
          // ligne abîmée (coupure de courant) : on garde la place pour ne pas décaler les numéros des autres opérations
          _ops.add({'seq': i, 'id': 'corrompu-$i', 'type': 'misc', 'device': '', 'at': '', 'data': <String, dynamic>{}});
        }
      }
    }
    _log('Journal chargé : ${_ops.length} opération(s).');
    Timer.periodic(const Duration(minutes: 30), (_) => _autoBackup());
    Timer.periodic(const Duration(seconds: 5), (_) => notifyListeners()); // met à jour « en ligne »
  }

  Future<void> saveConfig() async {
    await _cfgFile.writeAsString(jsonEncode({'key': key, 'port': port, 'autoStart': autoStart}));
  }

  Future<String?> start() async {
    if (_http != null) return null;
    try {
      final s = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _http = s;
      s.listen(_handle, onError: (Object e) => _log('Erreur réseau : $e'));
      _log('Serveur démarré sur le port $port.');
      notifyListeners();
      return null;
    } on SocketException catch (e) {
      final m = 'Impossible de démarrer sur le port $port (${e.osError?.message ?? e.message}). Un autre programme utilise peut-être ce port : essayez un autre numéro.';
      _log(m);
      return m;
    } catch (e) {
      final m = 'Impossible de démarrer : $e';
      _log(m);
      return m;
    }
  }

  Future<void> stop() async {
    await _http?.close(force: true);
    _http = null;
    _log('Serveur arrêté.');
  }

  Future<void> regenerateKey() async {
    key = _newKey();
    await saveConfig();
    _log('Nouvelle clé d’accès créée : à ressaisir dans chaque caisse.');
  }

  // ---------- Requêtes ----------
  bool _same(String a, String b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return d == 0;
  }

  bool _authorized(HttpRequest req) {
    final h = req.headers.value('authorization') ?? '';
    return h.startsWith('Bearer ') && _same(h.substring(7).trim(), key);
  }

  Future<void> _send(HttpRequest req, int code, Object body) async {
    final bytes = utf8.encode(jsonEncode(body));
    req.response.statusCode = code;
    req.response.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
    req.response.headers.contentLength = bytes.length;
    req.response.add(bytes);
    await req.response.close();
  }

  Future<void> _page(HttpRequest req) async {
    final html = '<!doctype html><html lang="fr"><meta charset="utf-8"><title>Mauzo Serveur</title>'
        '<body style="font-family:Segoe UI,Arial;margin:40px"><h1>Mauzo Serveur</h1>'
        '<p style="color:#0E8F4F;font-size:20px">En marche.</p><p>$opCount opération(s) enregistrée(s), $onlineCount caisse(s) connectée(s).</p>'
        '<p>Si vous voyez cette page depuis une autre caisse, le réseau et le pare-feu sont corrects : '
        'saisissez cette même adresse dans Mauzo POS, Paramètres, Réseau.</p></body></html>';
    final bytes = utf8.encode(html);
    req.response.statusCode = 200;
    req.response.headers.contentType = ContentType('text', 'html', charset: 'utf-8');
    req.response.headers.contentLength = bytes.length;
    req.response.add(bytes);
    await req.response.close();
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final path = req.uri.path;
      if (req.method == 'GET' && path == '/') return await _page(req);
      if (req.method == 'GET' && path == '/health') return await _send(req, 200, {'ok': true, 'name': 'Mauzo Serveur', 'ops': _ops.length});
      if (!_authorized(req)) return await _send(req, 401, {'error': 'clé d’accès invalide'});
      if (req.method == 'POST' && path == '/sync') return await _sync(req);
      if (req.method == 'GET' && path == '/feed') return await _feed(req);
      if (req.method == 'GET' && path == '/devices') return await _devicesList(req);
      return await _send(req, 404, {'error': 'route inconnue'});
    } catch (e) {
      _log('Erreur : $e');
      try {
        await _send(req, 500, {'error': 'erreur interne'});
      } catch (_) {}
    }
  }

  void _touch(String id, String name) {
    if (id.isEmpty) return;
    final d = devices[id];
    if (d == null) {
      devices[id] = Device(id, name.isEmpty ? id : name, DateTime.now());
      _log('Nouvelle caisse connectée : ${name.isEmpty ? id : name}.');
    } else {
      d.lastSeen = DateTime.now();
      if (name.isNotEmpty) d.name = name;
    }
  }

  void _append(Map<String, dynamic> rec) {
    _ops.add(rec);
    _ids.add(rec['id'] as String);
    _count(rec['type'] as String);
    try {
      _opsFile.writeAsStringSync('${jsonEncode(rec)}\n', mode: FileMode.append, flush: true);
    } catch (e) {
      _log('ERREUR d’écriture sur le disque : $e');
    }
  }

  Future<void> _sync(HttpRequest req) async {
    if (req.contentLength > 5 * 1024 * 1024) return _send(req, 413, {'error': 'envoi trop gros'});
    final text = await utf8.decoder.bind(req).join();
    Map<String, dynamic> body;
    try {
      body = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return _send(req, 400, {'error': 'JSON invalide'});
    }
    final ops = body['ops'];
    final device = (body['device'] as String?) ?? '';
    if (ops is! List || device.isEmpty) return _send(req, 400, {'error': 'ops ou device manquant'});
    _touch(device, (body['name'] as String?) ?? '');
    final done = <String>[];
    final errors = <Map<String, dynamic>>[];
    var added = 0;
    for (final o in ops.take(500)) {
      if (o is! Map) continue;
      final id = o['id'];
      if (id is! String || id.isEmpty || id.length > 120) continue;
      if (_ids.contains(id)) {
        done.add(id); // déjà reçue : on confirme sans rejouer
        continue;
      }
      final type = o['type'];
      final data = o['data'];
      if (type is! String || !_allowedTypes.contains(type) || data is! Map) {
        errors.add({'id': id, 'error': 'opération invalide'});
        done.add(id);
        continue;
      }
      _append({
        'seq': _ops.length + 1, 'id': id, 'type': type, 'label': '${o['label'] ?? ''}', 'device': device,
        'at': '${o['at'] ?? ''}', 'data': Map<String, dynamic>.from(data), 'received': DateTime.now().toIso8601String(),
      });
      done.add(id);
      added++;
    }
    if (added > 0) _log('$added opération(s) reçue(s) de ${devices[device]?.name ?? device}.');
    notifyListeners();
    await _send(req, 200, {'done': done, 'errors': errors});
  }

  Future<void> _feed(HttpRequest req) async {
    final q = req.uri.queryParameters;
    var since = int.tryParse(q['since'] ?? '0') ?? 0;
    final me = q['device'] ?? '';
    _touch(me, q['name'] ?? '');
    if (since < 0) since = 0;
    if (since > _ops.length) since = _ops.length; // journal réinitialisé : on recale la caisse
    final end = min(_ops.length, since + 500);
    final out = <Map<String, dynamic>>[];
    for (var i = since; i < end; i++) {
      final o = _ops[i];
      final dev = (o['device'] as String?) ?? '';
      // une caisse ne reçoit que les opérations des AUTRES caisses
      if (dev.isNotEmpty && dev != me) {
        out.add({'seq': i + 1, 'id': o['id'], 'type': o['type'], 'device': dev, 'at': o['at'], 'data': o['data']});
      }
    }
    await _send(req, 200, {'ops': out, 'last': end, 'more': end < _ops.length});
  }

  Future<void> _devicesList(HttpRequest req) => _send(req, 200, {
        'devices': [for (final d in devices.values) {'device': d.id, 'name': d.name, 'last_seen': d.lastSeen.toIso8601String()}],
      });

  // ---------- Sauvegarde ----------
  Future<String> backupNow() async {
    if (!await _opsFile.exists()) return 'Rien à sauvegarder pour l’instant.';
    final folder = Directory('${dir.path}${sep}sauvegardes');
    await folder.create(recursive: true);
    final n = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    final name = 'ops_${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}.jsonl';
    await _opsFile.copy('${folder.path}$sep$name');
    lastBackup = n;
    final files = await folder.list().where((e) => e is File).cast<File>().toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    while (files.length > 30) {
      await files.removeAt(0).delete();
    }
    _log('Sauvegarde créée : $name');
    return 'Sauvegarde créée : $name';
  }

  Future<void> _autoBackup() async {
    final n = DateTime.now();
    final l = lastBackup;
    if (l == null || l.day != n.day || l.month != n.month) await backupNow();
  }

  Future<void> openFolder() async {
    try {
      await Process.run('explorer', [dir.path]);
    } catch (_) {}
  }

  // ---------- Aides au diagnostic ----------
  Future<List<String>> localAddresses() async {
    final out = <String>[];
    try {
      for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final a in i.addresses) {
          if (!a.isLoopback) out.add(a.address);
        }
      }
    } catch (_) {}
    return out;
  }

  Future<String> openFirewall() async {
    try {
      final r = await Process.run('netsh', ['advfirewall', 'firewall', 'add', 'rule', 'name=MauzoServeur', 'dir=in', 'action=allow', 'protocol=TCP', 'localport=$port']);
      if (r.exitCode == 0) return 'Pare-feu : le port $port est maintenant autorisé.';
      return 'Pare-feu : autorisation refusée. Fermez l’application, puis relancez-la en administrateur (clic droit, « Exécuter en tant qu’administrateur ») et réessayez.';
    } catch (_) {
      return 'Pare-feu : impossible de lancer la commande. Autorisez le port $port dans le pare-feu Windows.';
    }
  }

  Future<_R> _call(HttpClient c, String method, String url, {Object? body, bool auth = true}) async {
    final req = method == 'POST' ? await c.postUrl(Uri.parse(url)) : await c.getUrl(Uri.parse(url));
    if (auth) req.headers.set('Authorization', 'Bearer $key');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    return _R(res.statusCode, await res.transform(utf8.decoder).join());
  }

  // Le serveur se teste lui-même : état, clé, dépôt d'une opération, lecture par une autre caisse, protection contre les doublons.
  Future<List<String>> selfTest() async {
    if (!running) return ['✗ Le serveur n’est pas démarré.'];
    final out = <String>[];
    final base = 'http://127.0.0.1:$port';
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final h = await _call(c, 'GET', '$base/health', auth: false);
      out.add(h.code == 200 ? '✓ Le serveur répond.' : '✗ /health a répondu ${h.code}.');
      final noKey = await _call(c, 'GET', '$base/feed?since=0&device=test-b', auth: false);
      out.add(noKey.code == 401 ? '✓ Sans la clé, l’accès est refusé.' : '✗ Accès sans clé : code ${noKey.code} (attendu 401).');
      final id = 'autotest-${DateTime.now().microsecondsSinceEpoch}';
      final op = {'id': id, 'type': 'misc', 'label': 'Autotest', 'data': {'test': true}, 'at': DateTime.now().toIso8601String()};
      final before = opCount;
      final s1 = await _call(c, 'POST', '$base/sync', body: {'device': 'test-a', 'name': 'Autotest A', 'ops': [op]});
      out.add(s1.code == 200 && s1.text.contains(id) ? '✓ Une opération est bien enregistrée.' : '✗ Dépôt d’opération : code ${s1.code}.');
      final f = await _call(c, 'GET', '$base/feed?since=${max(0, opCount - 3)}&device=test-b&name=Autotest%20B');
      out.add(f.code == 200 && f.text.contains(id) ? '✓ Une autre caisse reçoit l’opération.' : '✗ Lecture par une autre caisse : code ${f.code}.');
      final own = await _call(c, 'GET', '$base/feed?since=${max(0, opCount - 3)}&device=test-a');
      out.add(own.code == 200 && !own.text.contains(id) ? '✓ Une caisse ne reçoit pas ses propres opérations.' : '✗ La caisse a reçu sa propre opération.');
      await _call(c, 'POST', '$base/sync', body: {'device': 'test-a', 'ops': [op]});
      out.add(opCount == before + 1 ? '✓ Un envoi en double n’est pas enregistré deux fois.' : '✗ Doublon enregistré.');
    } catch (e) {
      out.add('✗ Test interrompu : $e');
    } finally {
      c.close();
    }
    notifyListeners();
    return out;
  }
}

final server = MauzoServer();
