// Prototype Flutter MVP - Grocery Route Optimizer
// Langue: Français
// But: ce fichier est une application Flutter "single-file" simplifiée pour tester le concept.
// Instructions:
// 1) Crée un nouveau projet Flutter: `flutter create grocery_route_mvp`
// 2) Remplace le contenu de `lib/main.dart` par ce fichier.
// 3) Lance avec `flutter run`.
// Remarque: pour garder le prototype facile à exécuter, j'ai utilisé uniquement Flutter SDK (pas de packages externes).
// Le projet embarque :
// - Catalogue fictif (300 items)
// - Plan de magasin simplifié (10 allées)
// - Interface pour ajouter des items à la "liste de courses"
// - Calcul d'ordre optimisé (heuristique TSP: nearest insertion + 2-opt)
// - Estimation du temps (vitesse de marche, pick time)
// - Visualisation simple du plan et du trajet

import 'dart:math';
import 'package:flutter/material.dart';

void main() {
  runApp(const GroceryRouteApp());
}

class GroceryRouteApp extends StatelessWidget {
  const GroceryRouteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Grocery Route MVP',
      theme: ThemeData(useMaterial3: true),
      home: const HomePage(),
    );
  }
}

// -------------------- Models --------------------
class Product {
  final int id;
  final String name;
  final int aisle; // 1..10
  final bool top; // true = haut du rayon, false = bas

  Product({required this.id, required this.name, required this.aisle, required this.top});
}

class PickPoint {
  final Product product;
  final int quantity;
  final Offset pos; // position on map coordinates

  PickPoint({required this.product, required this.quantity, required this.pos});
}

// -------------------- Fake Catalogue --------------------
List<Product> generateFakeCatalogue(int count) {
  final rng = Random(42);
  final categories = [
    'Fruits', 'Légumes', 'Viandes', 'Laitiers', 'Boulangerie', 'Épicerie', 'Boissons', 'Hygiène', 'Entretien', 'Surgelés'
  ];
  final names = [
    'Lait', 'Pâtes', 'Riz', 'Pain', 'Beurre', 'Tomates', 'Poulet', 'Fromage', 'Céréales', 'Yaourt', 'Café', 'Eau', 'Bière', 'Jus',
    'Shampoing', 'Savon', 'Lessive', 'Croquettes', 'Glace', 'Chips', 'Chocolat', 'Œufs', 'Haricots', 'Soupe', 'Sucre', 'Sel', 'Poivre'
  ];

  List<Product> out = [];
  for (int i = 0; i < count; i++) {
    final name = '${names[rng.nextInt(names.length)]} #${i + 1}';
    final aisle = rng.nextInt(10) + 1; // 1..10
    final top = rng.nextBool();
    out.add(Product(id: i + 1, name: name, aisle: aisle, top: top));
  }
  return out;
}

// -------------------- Map Geometry --------------------
class StoreMap {
  final int aisles = 10;
  final double aisleLength = 30.0; // meters (for ETA)
  final double aisleSpacing = 3.0; // meters
  final Offset entrance = const Offset(1, 11); // grid coord
  final Offset checkout = const Offset(5, 11);

  // Convert an aisle + top/bottom to a 2D position (grid coords)
  Offset pickPointFor(int aisle, bool top) {
    // Represent map as grid with columns = aisles (1..10 -> x index), rows: 0 (top walkway), 1..10 (aisles), 11 (bottom walkway)
    final x = aisle.toDouble();
    final y = top ? 1.0 : 10.0; // top near row 1, bottom near row 10
    return Offset(x, y);
  }
}

final storeMap = StoreMap();
final catalogue = generateFakeCatalogue(300);

// -------------------- Routing / TSP --------------------
// We'll implement a nearest-insertion TSP heuristic and 2-opt local improvement.

double euclidean(Offset a, Offset b) {
  return sqrt(pow(a.dx - b.dx, 2) + pow(a.dy - b.dy, 2));
}

List<int> nearestInsertion(List<Offset> pts) {
  // return order of indices
  final n = pts.length;
  if (n == 0) return [];
  if (n == 1) return [0];
  // start with 0 and the farthest point
  int far = 1;
  double maxd = -1;
  for (int i = 1; i < n; i++) {
    final d = euclidean(pts[0], pts[i]);
    if (d > maxd) {
      maxd = d;
      far = i;
    }
  }
  List<int> tour = [0, far];
  Set<int> inTour = {0, far};
  while (inTour.length < n) {
    // find nearest outside point to any in tour
    int bestOutside = -1;
    double bestDist = double.infinity;
    for (int i = 0; i < n; i++) {
      if (inTour.contains(i)) continue;
      for (int j in tour) {
        final d = euclidean(pts[i], pts[j]);
        if (d < bestDist) {
          bestDist = d;
          bestOutside = i;
        }
      }
    }
    // insert bestOutside into best position to minimize increase
    int bestPos = 0;
    double bestIncrease = double.infinity;
    for (int k = 0; k < tour.length; k++) {
      int a = tour[k];
      int b = tour[(k + 1) % tour.length];
      final increase = euclidean(pts[a], pts[bestOutside]) + euclidean(pts[bestOutside], pts[b]) - euclidean(pts[a], pts[b]);
      if (increase < bestIncrease) {
        bestIncrease = increase;
        bestPos = k + 1;
      }
    }
    tour.insert(bestPos, bestOutside);
    inTour.add(bestOutside);
  }
  return tour;
}

List<int> twoOpt(List<int> tour, List<Offset> pts) {
  bool improved = true;
  final n = tour.length;
  if (n <= 2) return tour;
  while (improved) {
    improved = false;
    for (int i = 0; i < n - 1; i++) {
      for (int k = i + 1; k < n; k++) {
        // try reversing tour[i+1..k]
        List<int> newTour = [];
        newTour.addAll(tour.sublist(0, i + 1));
        var rev = tour.sublist(i + 1, k + 1).reversed;
        newTour.addAll(rev);
        if (k + 1 < n) newTour.addAll(tour.sublist(k + 1));
        double oldLen = _tourLength(tour, pts);
        double newLen = _tourLength(newTour, pts);
        if (newLen + 1e-6 < oldLen) {
          tour = newTour;
          improved = true;
        }
        if (improved) break;
      }
      if (improved) break;
    }
  }
  return tour;
}

double _tourLength(List<int> tour, List<Offset> pts) {
  double sum = 0;
  for (int i = 0; i < tour.length - 1; i++) {
    sum += euclidean(pts[tour[i]], pts[tour[i + 1]]);
  }
  // from start (entrance) to first and last to checkout will be handled separately by caller
  return sum;
}

// -------------------- ETA Calculation --------------------
const double WALK_SPEED = 1.4; // m/s
const double PICK_TIME_PER_ITEM = 6.0; // seconds per item

// We map 'grid units' to meters: 1 grid unit (between adjacent aisle indices) corresponds to aisleSpacing (3m)

double gridToMeters(double gridUnits) {
  return gridUnits * storeMap.aisleSpacing; // rough
}

// -------------------- UI --------------------
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _searchCtl = TextEditingController();
  List<Product> results = [];
  List<PickPoint> picks = [];

  // computed plan
  List<Offset> plannedPathPoints = [];
  double estimatedSeconds = 0;

  @override
  void initState() {
    super.initState();
    results = catalogue.take(20).toList();
  }

  void _search(String q) {
    final s = q.toLowerCase().trim();
    setState(() {
      if (s.isEmpty) {
        results = catalogue.take(50).toList();
      } else {
        results = catalogue.where((p) => p.name.toLowerCase().contains(s)).take(50).toList();
      }
    });
  }

  void _addProduct(Product p) {
    final pos = storeMap.pickPointFor(p.aisle, p.top);
    setState(() {
      picks.add(PickPoint(product: p, quantity: 1, pos: pos));
    });
    _recomputeRoute();
  }

  void _removePick(int idx) {
    setState(() {
      picks.removeAt(idx);
    });
    _recomputeRoute();
  }

  void _recomputeRoute() {
    // prepare points list
    final entrance = storeMap.entrance;
    final checkout = storeMap.checkout;
    List<Offset> pts = picks.map((p) => p.pos).toList();

    if (pts.isEmpty) {
      setState(() {
        plannedPathPoints = [];
        estimatedSeconds = 0;
      });
      return;
    }

    // compute TSP order relative to entrance and checkout: we will build a tour from entrance -> pts ordered -> checkout
    // we perform nearest insertion on pts, then 2-opt
    List<int> order = nearestInsertion(pts);
    order = twoOpt(order, pts);

    // build full path from entrance to first, through ordered picks, to checkout
    List<Offset> path = [];
    path.add(entrance);
    for (int idx in order) path.add(pts[idx]);
    path.add(checkout);

    // compute approximate time: sum of euclidean distances converted to meters / walk speed + pick times
    double meters = 0;
    for (int i = 0; i < path.length - 1; i++) {
      final dGrid = euclidean(path[i], path[i + 1]);
      meters += gridToMeters(dGrid);
    }
    double walkSeconds = meters / WALK_SPEED;
    double picksSeconds = 0;
    for (var p in picks) {
      picksSeconds += PICK_TIME_PER_ITEM * p.quantity;
    }
    final totalSeconds = walkSeconds + picksSeconds;

    setState(() {
      plannedPathPoints = path;
      estimatedSeconds = totalSeconds;
    });
  }

  String _formatDuration(double seconds) {
    final s = seconds.round();
    final m = s ~/ 60;
    final rem = s % 60;
    return '${m}m ${rem}s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Grocery Route MVP')),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _searchCtl,
                  decoration: const InputDecoration(labelText: 'Rechercher un produit'),
                  onChanged: _search,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  _search(_searchCtl.text);
                },
                child: const Text('Chercher'),
              )
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Résultats', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Expanded(
                          child: ListView.builder(
                            itemCount: results.length,
                            itemBuilder: (context, index) {
                              final p = results[index];
                              return ListTile(
                                title: Text(p.name),
                                subtitle: Text('Allée ${p.aisle} - ${p.top ? 'haut' : 'bas'}'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.add),
                                  onPressed: () => _addProduct(p),
                                ),
                              );
                            },
                          ),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Liste de courses', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Expanded(
                          child: ListView.builder(
                            itemCount: picks.length,
                            itemBuilder: (context, index) {
                              final pick = picks[index];
                              return ListTile(
                                title: Text(pick.product.name),
                                subtitle: Text('Allée ${pick.product.aisle} - ${pick.product.top ? 'haut' : 'bas'}'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete),
                                  onPressed: () => _removePick(index),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('ETA: ${_formatDuration(estimatedSeconds)}'),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: _recomputeRoute,
                          child: const Text('Recalculer trajet'),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    flex: 4,
                    child: Container(
                      color: Colors.grey.shade100,
                      child: CustomPaint(
                        painter: StorePainter(storeMap: storeMap, picks: picks, path: plannedPathPoints),
                        child: Container(),
                      ),
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

// -------------------- Map Painter --------------------
class StorePainter extends CustomPainter {
  final StoreMap storeMap;
  final List<PickPoint> picks;
  final List<Offset> path;

  StorePainter({required this.storeMap, required this.picks, required this.path});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.0;
    final w = size.width;
    final h = size.height;

    // grid: columns 1..10 as aisles, rows 0..11
    final cols = 11; // index 0..11 to leave margin
    final rows = 12;
    final cellW = w / (cols + 1);
    final cellH = h / (rows + 1);

    // draw aisles as vertical rectangles
    for (int i = 1; i <= storeMap.aisles; i++) {
      final x = i * cellW;
      final rect = Rect.fromLTWH(x - cellW * 0.3, cellH * 1, cellW * 0.6, cellH * 9);
      final aislePaint = Paint()..color = Colors.grey.shade300;
      canvas.drawRect(rect, aislePaint);
      // label
      final tp = TextPainter(text: TextSpan(text: '$i', style: const TextStyle(color: Colors.black, fontSize: 12)), textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, 0));
    }

    // draw top and bottom walkway
    final walkwayPaint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, cellH * 0.9, w, cellH * 0.8), walkwayPaint);
    canvas.drawRect(Rect.fromLTWH(0, cellH * 10.2, w, cellH * 1.0), walkwayPaint);

    // helper to convert grid->pixel
    Offset toPixel(Offset gridPos) {
      final x = gridPos.dx * cellW;
      final y = gridPos.dy * cellH;
      return Offset(x, y);
    }

    // draw picks
    for (var p in picks) {
      final pixel = toPixel(p.pos);
      final pickPaint = Paint()..color = Colors.orange..style = PaintingStyle.fill;
      canvas.drawCircle(pixel, 8, pickPaint);
      final tp = TextPainter(text: TextSpan(text: p.product.name.split(' ').first, style: const TextStyle(color: Colors.black, fontSize: 10)), textDirection: TextDirection.ltr);
      tp.layout(maxWidth: 80);
      tp.paint(canvas, pixel + const Offset(10, -6));
    }

    // draw path
    if (path.isNotEmpty) {
      final pathPaint = Paint()..color = Colors.blue..style = PaintingStyle.stroke..strokeWidth = 3.0;
      final p = Path();
      p.moveTo(toPixel(path.first).dx, toPixel(path.first).dy);
      for (var pt in path.skip(1)) {
        final pixel = toPixel(pt);
        p.lineTo(pixel.dx, pixel.dy);
      }
      canvas.drawPath(p, pathPaint);

      // draw nodes
      for (var pt in path) {
        final pixel = toPixel(pt);
        canvas.drawCircle(pixel, 5, Paint()..color = Colors.blue);
      }
    }

    // entrance and checkout markers
    final ent = toPixel(storeMap.entrance);
    final chk = toPixel(storeMap.checkout);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: ent, width: 20, height: 12), const Radius.circular(4)), Paint()..color = Colors.green);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: chk, width: 28, height: 14), const Radius.circular(4)), Paint()..color = Colors.red);

    final tpEnt = TextPainter(text: const TextSpan(text: 'Entrée', style: TextStyle(color: Colors.white, fontSize: 10)), textDirection: TextDirection.ltr);
    tpEnt.layout();
    tpEnt.paint(canvas, ent - Offset(tpEnt.width / 2, tpEnt.height / 2));

    final tpChk = TextPainter(text: const TextSpan(text: 'Caisses', style: TextStyle(color: Colors.white, fontSize: 10)), textDirection: TextDirection.ltr);
    tpChk.layout();
    tpChk.paint(canvas, chk - Offset(tpChk.width / 2, tpChk.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// -------------------- End of file --------------------

/*
Notes & next steps (pour toi):
- Ce prototype est volontairement simple et utilise une conversion "grid->meters" approximative.
- L'optimisation TSP utilisée (nearest insertion + 2-opt) est heuristique et devrait être suffisante pour listes <= 40 items.
- Si tu veux, je peux :
  • ajouter A* sur un graphe d'intersections pour un routage plus réaliste,
  • transformer la gestion d'état vers Riverpod,
  • sauvegarder les listes localement (Hive) ou synchroniser via Firebase.

Dis-moi si tu veux que je génère aussi :
- le fichier pubspec.yaml prêt à l'emploi (avec dépendances si nécessaires),
- un APK debug,
- ou que je modifie le code pour utiliser Riverpod / Hive / A*.
*/
