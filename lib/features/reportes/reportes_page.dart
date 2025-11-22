// lib/features/reportes/reportes_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/api_client.dart';
import '../../core/env.dart';
import '../../core/responsive_utils.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../core/supabase_service.dart';
import 'reportes_create.dart';
import '../../core/ui.dart';

class ReportesPage extends StatefulWidget {
  final ApiClient api;
  const ReportesPage({super.key, required this.api});

  @override
  State<ReportesPage> createState() => _ReportesPageState();
}

class _ReportesPageState extends State<ReportesPage> with SingleTickerProviderStateMixin {
  late final String _base;
  late Future<_PageData> _future;
  late TabController _tabController;
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _base = Env.apiBaseUrl;
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _currentTab = _tabController.index;
          _future = _fetchAll();
        });
      }
    });
    _future = _fetchAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<_PageData> _fetchAll() async {
    final currentUserId = GetIt.instance<SupabaseService>().backendUserId;
    
    // Tab 0 = Para ti (todos), Tab 1 = Siguiendo (solo seguidos)
    http.Response r;
    if (_currentTab == 1 && currentUserId != null) {
      r = await http.get(Uri.parse('$_base/Reportes/seguidos/$currentUserId'));
    } else {
      r = await http.get(Uri.parse('$_base/Reportes?limit=50&offset=0&order=created_at.desc'));
    }
    
    if (r.statusCode != 200) {
      throw Exception('HTTP ${r.statusCode} al obtener Reportes');
    }
    final List<dynamic> raw = jsonDecode(r.body);
    final reports = raw
        .map((e) => Report.fromJson(e as Map<String, dynamic>))
        .toList();
    reports.sort((a, b) {
      final ta = a.createdAt;
      final tb = b.createdAt;
      if (tb != null && ta != null) return tb.compareTo(ta);
      if (tb != null) return 1;
      if (ta != null) return -1;
      return b.id.compareTo(a.id);
    });

    final ids = reports.map((e) => e.userId).toSet().toList();
    final names = <int, String>{};
    if (ids.isNotEmpty) {
      bool bulkOk = false;
      try {
        final bulk = await http.get(Uri.parse('$_base/users/bulk?ids=${ids.join(',')}'));
        if (bulk.statusCode == 200) {
          final List list = jsonDecode(bulk.body);
          for (final it in list) {
            if (it is Map<String, dynamic>) {
              final id = (it['id'] as num?)?.toInt();
              if (id != null) {
                names[id] = (it['user'] ?? 'Usuario $id').toString();
              }
            }
          }
          bulkOk = true;
        }
      } catch (_) {}
      if (!bulkOk || names.length < ids.length) {
        final missing = ids.where((id) => !names.containsKey(id));
        await Future.wait(
          missing.map((id) async {
            try {
              final u = await http.get(Uri.parse('$_base/users/$id'));
              if (u.statusCode == 200) {
                final data = jsonDecode(u.body);
                names[id] = (data is Map && data['user'] != null)
                    ? data['user'].toString()
                    : 'Usuario $id';
              } else {
                names[id] = 'Usuario $id';
              }
            } catch (_) {
              names[id] = 'Usuario $id';
            }
          }),
        );
      }
    }

    final imagenesPorReporte = <int, List<String>>{};
    if (reports.isNotEmpty) {
      bool bulkOk = false;
      try {
        final rids = reports.map((e) => e.id).join(',');
        final adjRes = await http.get(Uri.parse('$_base/Adjunto/by-reporte-ids?ids=$rids'));
        if (adjRes.statusCode == 200) {
          final adjuntos = jsonDecode(adjRes.body) as List<dynamic>;
          for (final adj in adjuntos) {
            if (adj is Map<String, dynamic> &&
                adj['reporte_id'] != null &&
                adj['url'] != null) {
              final tipo = adj['tipo']?.toString().toLowerCase();
              final url = (adj['url'] as String).toString();
              const tiposValidos = {
                'foto', 'imagen', 'image', 'img', 'picture', 'photo',
              };
              final lowerUrl = url.toLowerCase();
              const exts = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.svg', '.heic', '.heif'];
              final looksLikeImage = exts.any((e) => lowerUrl.contains(e));
              if ((tipo != null && tiposValidos.contains(tipo)) ||
                  (tipo == null || tipo.isEmpty) && looksLikeImage) {
                final rid = (adj['reporte_id'] as num).toInt();
                imagenesPorReporte.putIfAbsent(rid, () => []).add(url);
              }
            }
          }
          bulkOk = true;
        }
      } catch (_) {}
      if (!bulkOk) {
        await Future.wait(
          reports.map((rep) async {
            try {
              final resAdj = await http.get(Uri.parse('$_base/Adjunto/reporte/${rep.id}'));
              if (resAdj.statusCode == 200) {
                final adjuntos = jsonDecode(resAdj.body) as List<dynamic>;
                for (final adj in adjuntos) {
                  if (adj is Map<String, dynamic> && adj['url'] != null) {
                    final url = (adj['url'] as String).toString();
                    final lowerUrl = url.toLowerCase();
                    const exts = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.svg', '.heic', '.heif'];
                    final looksLikeImage = exts.any((e) => lowerUrl.contains(e));
                    if (looksLikeImage) {
                      imagenesPorReporte.putIfAbsent(rep.id, () => []).add(url);
                    }
                  }
                }
              }
            } catch (_) {}
          }),
        );
      }
    }

    // Traer reacciones del usuario (si está logueado en backend)
    final userReactions = <int, _UserReaction>{};
    if (currentUserId != null) {
      try {
        final rr = await http.get(
          Uri.parse('$_base/Reacciones/user/$currentUserId'),
        );
        if (rr.statusCode == 200) {
          final list = jsonDecode(rr.body) as List<dynamic>;
          for (final it in list) {
            if (it is Map<String, dynamic>) {
              final rid = it['reporte_id'] as int?;
              final id = it['id'] as int?;
              final tipo = (it['tipo'] as String?)?.toLowerCase();
              if (rid != null &&
                  id != null &&
                  (tipo == 'upvote' || tipo == 'downvote')) {
                userReactions[rid] = _UserReaction(id: id, tipo: tipo!);
              }
            }
          }
        }
      } catch (_) {}
    }

    return _PageData(
      reports: reports,
      userNames: names,
      imagenesPorReporte: imagenesPorReporte,
      userReactions: userReactions,
      currentUserId: currentUserId,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _fetchAll());
    await _future;
  }

  // ⬇️ IMPORTANTE: este build DEBE existir, con esta firma exacta
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E2D52),
      appBar: AppBar(
        backgroundColor: const Color(0xFF08192D),
        foregroundColor: Colors.white,
        toolbarHeight: 56,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Mapa de calor (Lima)',
                  icon: const Icon(Icons.map_outlined),
                  onPressed: () => context.push('/mapa'),
                ),
                IconButton(
                  tooltip: 'Ranking distritos seguros',
                  icon: const Icon(Icons.security),
                  onPressed: () => context.push('/ranking-distritos'),
                ),
                IconButton(
                  tooltip: 'Nuevo reporte',
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () async {
                    final result = await showDialog<bool>(
                      context: context,
                      builder: (ctx) {
                        final dialogWidth = ResponsiveHelper.isMobile(ctx) 
                            ? MediaQuery.of(ctx).size.width * 0.95
                            : 420.0;
                        return AlertDialog(
                          backgroundColor: Colors.white,
                          contentPadding: ResponsiveHelper.getPadding(ctx, factor: 0.67),
                          content: SizedBox(width: dialogWidth, child: ReportesCreateForm()),
                        );
                      },
                    );
                    if (result == true) {
                      _refresh();
                    }
                  },
                ),
              ],
            ),
            SizedBox(
              height: 36,
              child: Image.asset('assets/logo.png', fit: BoxFit.contain),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Mi perfil',
                  icon: const Icon(Icons.person_outline),
                  onPressed: () => context.push('/profile'),
                ),
                IconButton(
                  tooltip: 'Cerrar sesión',
                  icon: const Icon(Icons.logout),
                  onPressed: () async {
                    try {
                      await GetIt.instance<SupabaseService>().signOut();
                      if (context.mounted) context.go('/login');
                    } catch (_) {}
                  },
                ),
              ],
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF1E88E5),
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.normal),
          tabs: const [
            Tab(text: 'Para ti'),
            Tab(text: 'Siguiendo'),
          ],
        ),
      ),
      body: FutureBuilder<_PageData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            final maxWidth = ResponsiveHelper.getMaxContentWidth(context);
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: _ErrorView(
                  message: snap.error.toString(),
                  onRetry: _refresh,
                ),
              ),
            );
          }
          final data = snap.data!;
          if (data.reports.isEmpty) {
            final maxWidth = ResponsiveHelper.getMaxContentWidth(context);
            final padding = ResponsiveHelper.getPadding(context);
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                children: [
                  SizedBox(height: ResponsiveHelper.getVerticalSpacing(context) * 3),
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: padding.left),
                        child: Column(
                          children: const [
                            SizedBox(height: 120),
                            Icon(
                              Icons.inbox_outlined,
                              color: Colors.white70,
                              size: 48,
                            ),
                            SizedBox(height: 12),
                            Center(
                              child: Text(
                                'No hay reportes aún',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                            SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          final maxWidth = ResponsiveHelper.getMaxContentWidth(context);
          final horizontalPadding = ResponsiveHelper.getHorizontalSpacing(context) * 0.75;
          final verticalPadding = ResponsiveHelper.getVerticalSpacing(context) * 0.5;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              padding: EdgeInsets.symmetric(vertical: verticalPadding),
              itemCount: data.reports.length,
              itemBuilder: (context, i) {
                final r = data.reports[i];
                final user = data.userNames[r.userId] ?? 'Usuario ${r.userId}';
                final imagenes = data.imagenesPorReporte[r.id];
                final reaction = data.userReactions[r.id];
                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: verticalPadding * 0.5,
                      ),
                      child: InkWell(
                        onTap: () => context.push('/reportes/${r.id}'),
                        borderRadius: BorderRadius.circular(4),
                        child: _ReportCard(
                          report: r,
                          userName: user,
                          imagenes: imagenes,
                          userReaction: reaction,
                          currentUserId: data.currentUserId,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class Report {
  final int userId;
  final String titulo;
  final String descripcion;
  final String categoria;
  final double? lat;
  final double? lon;
  final String direccion;
  final String estado;
  final double? veracidad;
  final int upvotes;
  final int downvotes;
  final int id;
  final DateTime? createdAt;

  Report({
    required this.userId,
    required this.titulo,
    required this.descripcion,
    required this.categoria,
    required this.lat,
    required this.lon,
    required this.direccion,
    required this.estado,
    required this.veracidad,
    required this.id,
    required this.upvotes,
    required this.downvotes,
    required this.createdAt,
  });

  factory Report.fromJson(Map<String, dynamic> j) {
    double? asD(v) =>
        v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
    DateTime? asT(v) {
      if (v == null) return null;
      try {
        return DateTime.parse('$v');
      } catch (_) {
        return null;
      }
    }

    return Report(
      userId: j['user_id'] as int,
      titulo: '${j['titulo'] ?? ''}',
      descripcion: '${j['descripcion'] ?? ''}',
      categoria: '${j['categoria'] ?? ''}',
      lat: asD(j['lat']),
      lon: asD(j['lon']),
      direccion: '${j['direccion'] ?? ''}',
      estado: '${j['estado'] ?? ''}',
      veracidad: asD(j['veracidad_porcentaje']),
      id: j['id'] as int,
      upvotes: (j['cantidad_upvotes'] as int?) ?? 0,
      downvotes: (j['cantidad_downvotes'] as int?) ?? 0,
      createdAt: asT(j['created_at']),
    );
  }
}

class _PageData {
  final List<Report> reports;
  final Map<int, String> userNames;
  final Map<int, List<String>>
  imagenesPorReporte; // reporte_id -> lista de urls
  final Map<int, _UserReaction>
  userReactions; // reporte_id -> reaccion del usuario
  final int? currentUserId;
  _PageData({
    required this.reports,
    required this.userNames,
    required this.imagenesPorReporte,
    required this.userReactions,
    required this.currentUserId,
  });
}

class _UserReaction {
  final int id;
  final String tipo; // 'upvote' | 'downvote'
  const _UserReaction({required this.id, required this.tipo});
}

class _ReportCard extends StatefulWidget {
  final Report report;
  final String userName;
  final List<String>? imagenes;
  final _UserReaction? userReaction;
  final int? currentUserId;
  const _ReportCard({
    Key? key,
    required this.report,
    required this.userName,
    this.imagenes,
    this.userReaction,
    this.currentUserId,
  }) : super(key: key);

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  final String _base = Env.apiBaseUrl;
  late int _upvotes;
  late int _downvotes;
  bool _updatingUp = false;
  bool _updatingDown = false;
  int? _reactionId; // id en tabla Reaccion
  String? _reactionTipo; // 'upvote' | 'downvote' | null
  double? _veracidad; // porcentaje (0-100)
  String? _estado; // estado visible en la tarjeta
  // Comentarios
  bool _commentsOpen = false;
  bool _loadingComments = false;
  bool _postingComment = false;
  final TextEditingController _commentCtrl = TextEditingController();
  List<_Comment> _comments = [];
  final Map<int, String> _usersCache = {};

  @override
  void initState() {
    super.initState();
    _upvotes = widget.report.upvotes;
    _downvotes = widget.report.downvotes;
    _reactionId = widget.userReaction?.id;
    _reactionTipo = widget.userReaction?.tipo;
  _veracidad = widget.report.veracidad;
  _estado = widget.report.estado;
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Color _estadoColor(String s) {
    switch (s.toUpperCase()) {
      case 'ACTIVO':
        return Colors.orange;
      case 'RESUELTO':
      case 'CERRADO':
        return Colors.green;
      case 'EN PROCESO':
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }

  Future<void> _vote({required bool up}) async {
    if (widget.currentUserId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Inicia sesión para votar')));
      return;
    }
    if (up && _updatingUp) return;
    if (!up && _updatingDown) return;

    final wasTipo = _reactionTipo; // estado previo
    final wasId = _reactionId;
    // Calcular nuevo estado y contadores optimistas
    String? newTipo = wasTipo;
    int upvotes = _upvotes;
    int downvotes = _downvotes;

    if (up) {
      if (wasTipo == 'upvote') {
        // toggle off upvote
        newTipo = null;
        upvotes = (_upvotes - 1).clamp(0, 1 << 31);
      } else if (wasTipo == 'downvote') {
        // cambiar down->up
        newTipo = 'upvote';
        upvotes = _upvotes + 1;
        downvotes = (_downvotes - 1).clamp(0, 1 << 31);
      } else {
        // no había reacción, crear upvote
        newTipo = 'upvote';
        upvotes = _upvotes + 1;
      }
    } else {
      if (wasTipo == 'downvote') {
        // toggle off downvote
        newTipo = null;
        downvotes = (_downvotes - 1).clamp(0, 1 << 31);
      } else if (wasTipo == 'upvote') {
        // cambiar up->down
        newTipo = 'downvote';
        upvotes = (_upvotes - 1).clamp(0, 1 << 31);
        downvotes = _downvotes + 1;
      } else {
        // no había reacción, crear downvote
        newTipo = 'downvote';
        downvotes = _downvotes + 1;
      }
    }

    setState(() {
      if (up)
        _updatingUp = true;
      else
        _updatingDown = true;
      _upvotes = upvotes;
      _downvotes = downvotes;
      _reactionTipo = newTipo;
    });

    try {
      // 1) Persistir reaccion
      if (newTipo == null) {
        // eliminar reaccion existente
        if (wasId != null) {
          final del = await http.delete(Uri.parse('$_base/Reacciones/$wasId'));
          if (del.statusCode < 200 || del.statusCode >= 300) {
            throw Exception('DELETE reaccion HTTP ${del.statusCode}');
          }
          _reactionId = null;
        }
      } else if (wasId == null) {
        // crear nueva
        final res = await http.post(
          Uri.parse('$_base/Reacciones'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'reporte_id': widget.report.id,
            'user_id': widget.currentUserId,
            'tipo': newTipo,
          }),
        );
        if (res.statusCode != 201) {
          throw Exception('POST reaccion HTTP ${res.statusCode}');
        }
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _reactionId = data['id'] as int?;
        _reactionTipo = newTipo;
      } else {
        // actualizar tipo existente
        final res = await http.patch(
          Uri.parse('$_base/Reacciones/$wasId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'tipo': newTipo}),
        );
        if (res.statusCode != 200) {
          throw Exception('PATCH reaccion HTTP ${res.statusCode}');
        }
        _reactionId = wasId;
        _reactionTipo = newTipo;
      }

      // 2) Persistir contadores del reporte
      final patchBody = <String, dynamic>{
        'cantidad_upvotes': _upvotes,
        'cantidad_downvotes': _downvotes,
      };
      final pr = await http.patch(
        Uri.parse('$_base/Reportes/${widget.report.id}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(patchBody),
      );
      if (pr.statusCode != 200) {
        throw Exception('PATCH reporte HTTP ${pr.statusCode}');
      }
      // actualizar veracidad/estado local desde respuesta o calcular fallback
      try {
        final body = jsonDecode(pr.body);
        double? vSrv;
        String? estadoSrv;
        if (body is Map<String, dynamic>) {
          final num? vNum = body['veracidad_porcentaje'] as num?;
          vSrv = vNum?.toDouble();
          final es = body['estado'];
          if (es is String && es.isNotEmpty) {
            estadoSrv = es;
          }
        }
        setState(() {
          if (vSrv != null) {
            _veracidad = vSrv;
          } else {
            final total = _upvotes + _downvotes;
            _veracidad = total > 0 ? (_upvotes / total) * 100.0 : 0.0;
          }
          if (estadoSrv != null) {
            _estado = estadoSrv;
          } else {
            final v = _veracidad;
            if (v != null) {
              _estado = v < 33.0 ? 'Falso' : 'Activo';
            }
          }
        });
      } catch (_) {
        setState(() {
          final total = _upvotes + _downvotes;
          _veracidad = total > 0 ? (_upvotes / total) * 100.0 : 0.0;
          final v = _veracidad;
          if (v != null) {
            _estado = v < 33.0 ? 'Falso' : 'Activo';
          }
        });
      }
    } catch (e) {
      // revertir a estado previo
      setState(() {
        _reactionTipo = wasTipo;
        _reactionId = wasId;
        _upvotes = widget.report.upvotes;
        _downvotes = widget.report.downvotes;
        _veracidad = widget.report.veracidad;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo registrar tu voto: $e')),
      );
    } finally {
      setState(() {
        if (up)
          _updatingUp = false;
        else
          _updatingDown = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _veracidad;
    final vTxt = v == null ? '—' : '${v.toStringAsFixed(0)}%';
    final created = widget.report.createdAt;
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: const Color(0xFF08192D), width: 1),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Columna de votos (estilo Reddit)
            Container(
              width: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF08192D),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  bottomLeft: Radius.circular(4),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: _updatingUp ? null : () => _vote(up: true),
                    icon: _updatingUp
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _reactionTipo == 'upvote'
                                ? Icons.arrow_upward
                                : Icons.arrow_upward_outlined,
                            color: _reactionTipo == 'upvote'
                                ? Colors.orange
                                : Colors.grey[400],
                          ),
                  ),
                  const SizedBox(height: 4),
                  // Mostrar conteos individuales por separado
                  Text(
                    '$_upvotes',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[400],
                    ),
                  ),
                  const SizedBox(height: 8),
                  IconButton(
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: _updatingDown ? null : () => _vote(up: false),
                    icon: _updatingDown
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _reactionTipo == 'downvote'
                                ? Icons.arrow_downward
                                : Icons.arrow_downward_outlined,
                            color: _reactionTipo == 'downvote'
                                ? Colors.blue
                                : Colors.grey[400],
                          ),
                  ),
                      const SizedBox(height: 4),
                      Text(
                        '$_downvotes',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[400],
                        ),
                      ),
                ],
              ),
            ),
            // Contenido principal
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header compacto: usuario, tiempo, estado
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 14,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () {
                            context.push('/profile/${widget.report.userId}');
                          },
                          child: Text(
                            widget.userName,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.lightBlue[200],
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                              decorationColor: Colors.lightBlue[200],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (created != null) ...[
                          Text(
                            '• ${relativeTimeString(created)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _estadoColor(
                              (_estado ?? widget.report.estado),
                            ).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _estadoColor(
                                (_estado ?? widget.report.estado),
                              ).withOpacity(0.5),
                            ),
                          ),
                          child: Text(
                            (_estado ?? widget.report.estado),
                            style: TextStyle(
                              fontSize: 10,
                              color: _estadoColor((_estado ?? widget.report.estado)),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Título
                    Text(
                      widget.report.titulo.isEmpty
                          ? 'Reporte #${widget.report.id}'
                          : widget.report.titulo,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    // Descripción más compacta
                    Text(
                      widget.report.descripcion.trim().isEmpty
                          ? 'Sin descripción'
                          : widget.report.descripcion.trim(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey[300],
                        height: 1.4,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.imagenes != null &&
                        widget.imagenes!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _ImageGallery(
                        images: widget.imagenes!,
                        onImageTap: (index) => _openImageViewer(
                          context,
                          widget.imagenes!,
                          startIndex: index,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    // Footer compacto: ubicación, categoría, veracidad
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        if (widget.report.categoria.isNotEmpty)
                          _CompactInfo(
                            icon: Icons.category_outlined,
                            text: widget.report.categoria,
                          ),
                        if (widget.report.direccion.isNotEmpty)
                          _CompactInfo(
                            icon: Icons.place_outlined,
                            text: widget.report.direccion,
                            maxWidth: 200,
                          ),
                        _CompactInfo(
                          icon: Icons.verified_outlined,
                          text: 'Veracidad: $vTxt',
                          color: v != null && v > 50
                              ? Colors.green
                              : Colors.orange,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Divider(height: 1, color: Colors.grey[800]),
                    const SizedBox(height: 8),
                    // Comentarios
                    _buildCommentsSection(theme),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentsSection(ThemeData theme) {
    final count = _comments.isNotEmpty || _loadingComments
        ? _comments.length
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: () async {
                setState(() => _commentsOpen = !_commentsOpen);
                if (_commentsOpen && _comments.isEmpty && !_loadingComments) {
                  await _loadComments();
                }
              },
              icon: Icon(
                _commentsOpen ? Icons.expand_less : Icons.comment_outlined,
                size: 18,
              ),
              label: Text(
                'Comentarios' + (count != null ? ' ($count)' : ''),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const Spacer(),
            if (_loadingComments)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        if (_commentsOpen) ...[
          const SizedBox(height: 6),
          if (_loadingComments)
            const SizedBox(height: 0)
          else ...[
            // Lista de comentarios
            if (_comments.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Text(
                  'Aún no hay comentarios. ¡Sé el primero en comentar!',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              )
            else
              Column(
                children: _comments
                    .map(
                      (c) => _CommentTile(
                        userName:
                            _usersCache[c.userId] ?? 'Usuario ${c.userId}',
                        message: c.mensaje,
                        createdAt: c.createdAt,
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 8),
            // Caja para nuevo comentario
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentCtrl,
                    maxLines: null,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: widget.currentUserId == null
                          ? 'Inicia sesión para comentar'
                          : 'Escribe un comentario…',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF0E2D52).withOpacity(0.5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[800]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[800]!),
                      ),
                    ),
                    enabled: !_postingComment,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Enviar comentario',
                  onPressed: _postingComment ? null : _postComment,
                  icon: _postingComment
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  Future<void> _loadComments() async {
    setState(() => _loadingComments = true);
    try {
      final res = await http.get(
        Uri.parse('$_base/Comentarios/reporte/${widget.report.id}'),
      );
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode} al obtener comentarios');
      }
      final List<dynamic> list = jsonDecode(res.body) as List<dynamic>;
      final List<_Comment> parsed = list
          .whereType<Map<String, dynamic>>()
          .map((e) => _Comment.fromJson(e))
          .toList();
      // Orden por fecha asc (antiguo->reciente)
      parsed.sort((a, b) {
        final ta = a.createdAt;
        final tb = b.createdAt;
        if (ta != null && tb != null) return ta.compareTo(tb);
        if (ta != null) return -1;
        if (tb != null) return 1;
        return a.id.compareTo(b.id);
      });

      // Cargar nombres de usuario faltantes
      final Set<int> missingIds = parsed.map((e) => e.userId).toSet()
        ..removeWhere((int id) => _usersCache.containsKey(id));
      await Future.wait(
        missingIds.map((int id) async {
          try {
            final u = await http.get(Uri.parse('$_base/users/$id'));
            if (u.statusCode == 200) {
              final data = jsonDecode(u.body);
              _usersCache[id] = (data is Map && data['user'] != null)
                  ? data['user'].toString()
                  : 'Usuario $id';
            } else {
              _usersCache[id] = 'Usuario $id';
            }
          } catch (_) {
            _usersCache[id] = 'Usuario $id';
          }
        }),
      );

      setState(() => _comments = parsed);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudieron cargar comentarios: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingComments = false);
    }
  }

  Future<void> _postComment() async {
    if (widget.currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sesión para comentar')),
      );
      return;
    }
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El comentario no puede estar vacío')),
      );
      return;
    }
    setState(() => _postingComment = true);
    try {
      final res = await http.post(
        Uri.parse('$_base/Comentarios'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'reporte_id': widget.report.id,
          'user_id': widget.currentUserId,
          'mensaje': text,
        }),
      );
      if (res.statusCode != 201) {
        throw Exception('HTTP ${res.statusCode} al crear comentario');
      }
      final Map<String, dynamic> body = jsonDecode(res.body);
      final _Comment created = _Comment.fromJson(body);
      // Asegurar nombre del usuario actual en cache
      final uid = created.userId;
      if (!_usersCache.containsKey(uid)) {
        try {
          final u = await http.get(Uri.parse('$_base/users/$uid'));
          if (u.statusCode == 200) {
            final data = jsonDecode(u.body);
            _usersCache[uid] = (data is Map && data['user'] != null)
                ? data['user'].toString()
                : 'Usuario $uid';
          } else {
            _usersCache[uid] = 'Usuario $uid';
          }
        } catch (_) {
          _usersCache[uid] = 'Usuario $uid';
        }
      }
      setState(() {
        _comments = [..._comments, created];
        _commentCtrl.clear();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo publicar el comentario: $e')),
      );
    } finally {
      if (mounted) setState(() => _postingComment = false);
    }
  }
}

class _Comment {
  final int id;
  final int reporteId;
  final int userId;
  final String mensaje;
  final DateTime? createdAt;

  _Comment({
    required this.id,
    required this.reporteId,
    required this.userId,
    required this.mensaje,
    required this.createdAt,
  });

  factory _Comment.fromJson(Map<String, dynamic> j) {
    DateTime? asT(v) {
      if (v == null) return null;
      try {
        return DateTime.parse('$v');
      } catch (_) {
        return null;
      }
    }

    return _Comment(
      id: (j['id'] as num?)?.toInt() ?? 0,
      reporteId: (j['reporte_id'] as num).toInt(),
      userId: (j['user_id'] as num).toInt(),
      mensaje: '${j['mensaje'] ?? ''}',
      createdAt: asT(j['created_at']),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final String userName;
  final String message;
  final DateTime? createdAt;

  const _CommentTile({
    required this.userName,
    required this.message,
    required this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.person_outline, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      userName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (createdAt != null)
                      Text(
                        '• ${relativeTimeString(createdAt!)}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style:
                      theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        color: Colors.grey[900],
                      ) ??
                      TextStyle(fontSize: 13, color: Colors.grey[900]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Widget auxiliar para información compacta
class _CompactInfo extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  final double? maxWidth;

  const _CompactInfo({
    required this.icon,
    required this.text,
    this.color,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color ?? Colors.grey[500]),
        const SizedBox(width: 4),
        Flexible(
          child: Container(
            constraints: maxWidth != null
                ? BoxConstraints(maxWidth: maxWidth!)
                : null,
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: color ?? Colors.grey[400]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}

// Widget para galería de imágenes mejorado
class _ImageGallery extends StatefulWidget {
  final List<String> images;
  final Function(int) onImageTap;

  const _ImageGallery({required this.images, required this.onImageTap});

  @override
  State<_ImageGallery> createState() => _ImageGalleryState();
}

class _ImageGalleryState extends State<_ImageGallery> {
  late final PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Contenedor de tamaño fijo estilo Reddit
    // Siempre el mismo alto independiente de cuántas imágenes haya
    return Container(
      height: 320, // Altura fija como Reddit
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: const Color(0xFF08192D),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _buildImageContent(),
      ),
    );
  }

  Widget _buildImageContent() {
    // Mostrar SIEMPRE como carrusel (PageView), incluso con 1 o 2 imágenes
    return _buildPageView();
  }

  Widget _buildPageView() {
    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          itemCount: widget.images.length,
          onPageChanged: (index) {
            setState(() => _currentIndex = index);
          },
          itemBuilder: (ctx, idx) {
            return GestureDetector(
              onTap: () => widget.onImageTap(idx),
              child: _buildSingleImageFixed(widget.images[idx], idx),
            );
          },
        ),
        // Indicadores de página (dots)
        if (widget.images.length > 1)
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.images.length,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentIndex == index
                        ? Colors.white
                        : Colors.white.withOpacity(0.4),
                  ),
                ),
              ),
            ),
          ),
        // Contador en esquina (sólo si hay más de 1 imagen)
        if (widget.images.length > 1)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.photo_library, size: 14, color: Colors.white),
                  const SizedBox(width: 5),
                  Text(
                    '${_currentIndex + 1}/${widget.images.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Flechas de navegación (prev/next) para carrusel
        if (widget.images.length > 1)
          Positioned(
            left: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: _NavButton(
                icon: Icons.chevron_left,
                onPressed: _currentIndex > 0
                    ? () => _pageController.previousPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        )
                    : null,
              ),
            ),
          ),
        if (widget.images.length > 1)
          Positioned(
            right: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: _NavButton(
                icon: Icons.chevron_right,
                onPressed: _currentIndex < widget.images.length - 1
                    ? () => _pageController.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        )
                    : null,
              ),
            ),
          ),
      ],
    );
  }

  // Método simplificado para mostrar imagen en contenedor fijo estilo Reddit
  Widget _buildSingleImageFixed(String url, int index) {
    return GestureDetector(
      onTap: () => widget.onImageTap(index),
      child: Container(
        color: const Color(0xFF08192D),
        child: Image.network(
          url,
          fit: BoxFit
              .contain, // La imagen se ajusta al contenedor manteniendo proporción
          width: double.infinity,
          height: double.infinity,
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded /
                          progress.expectedTotalBytes!
                    : null,
                strokeWidth: 2,
              ),
            );
          },
          errorBuilder: (ctx, err, stack) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image, size: 48, color: Colors.grey[600]),
                const SizedBox(height: 8),
                Text(
                  'Error al cargar imagen',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _openImageViewer(
  BuildContext context,
  List<String> urls, {
  int startIndex = 0,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ImageViewer(urls: urls, initialIndex: startIndex),
    ),
  );
}

class _ImageViewer extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  const _ImageViewer({Key? key, required this.urls, this.initialIndex = 0})
    : super(key: key);

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${widget.initialIndex + 1}/${widget.urls.length}'),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.urls.length,
        itemBuilder: (_, i) {
          final url = widget.urls[i];
          return Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image,
                  color: Colors.white70,
                  size: 64,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// Botón circular para navegar en el carrusel
class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _NavButton({required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: enabled ? 0.9 : 0.4,
      child: Material(
        color: Colors.black.withOpacity(0.5),
        shape: const CircleBorder(),
        child: IconButton(
          icon: Icon(icon, color: Colors.white),
          onPressed: onPressed,
          tooltip: icon == Icons.chevron_left ? 'Anterior' : 'Siguiente',
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({Key? key, required this.message, required this.onRetry})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            const Text(
              'Error cargando datos',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
