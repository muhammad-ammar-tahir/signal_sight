import 'dart:math';

/// Channel congestion scoring helpers
class ChannelUtils {
  /// Gaussian overlap weight: how much does channel `other` interfere with channel `target`?
  static double overlapWeight(int target, int other, {bool is5GHz = false}) {
    if (is5GHz) {
      // 5 GHz channels are non-overlapping if separated by 4+ channels (20 MHz wide)
      return (target - other).abs() < 2 ? 1.0 : 0.0;
    }
    // 2.4 GHz: channels overlap within ±4
    final diff = (target - other).abs();
    if (diff == 0) return 1.0;
    if (diff >= 5) return 0.0;
    return 1.0 - diff / 5.0;
  }

  /// Compute per-channel congestion score (0–100)
  static Map<int, double> computeCongestion(
    List<({int channel, int rssi})> aps, {
    bool is5GHz = false,
  }) {
    final channels = is5GHz
        ? [36, 40, 44, 48, 52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 149, 153, 157, 161, 165]
        : List.generate(13, (i) => i + 1);

    final scores = <int, double>{};
    for (final ch in channels) {
      double score = 0.0;
      for (final ap in aps) {
        final w = overlapWeight(ch, ap.channel, is5GHz: is5GHz);
        if (w > 0) {
          // Convert RSSI to linear power ratio (-30 dBm = 1.0, -90 dBm ≈ 0.001)
          final power = pow(10, (ap.rssi + 30) / 10.0).toDouble();
          score += w * power;
        }
      }
      scores[ch] = score;
    }
    // Normalize to 0–100
    final maxScore = scores.values.fold(0.0, max);
    if (maxScore == 0) return {for (final ch in channels) ch: 0.0};
    return scores.map((k, v) => MapEntry(k, (v / maxScore) * 100));
  }

  /// Find top 3 least congested channels
  static List<({int channel, double score})> bestChannels(
    Map<int, double> congestion,
  ) {
    final sorted = congestion.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return sorted.take(3).map((e) => (channel: e.key, score: e.value)).toList();
  }
}

/// Security string classifier
class SecurityUtils {
  static String classify(String capabilities) {
    final cap = capabilities.toUpperCase();
    if (cap.isEmpty || cap.contains('[ESS]') && !cap.contains('WPA') && !cap.contains('WEP')) {
      return 'Open';
    }
    if (cap.contains('WPA3')) return 'Strong';
    if (cap.contains('WPA2-EAP') || cap.contains('WPA2-Enterprise')) return 'Strong';
    if (cap.contains('WPA2') || cap.contains('RSN')) return 'Caution';
    if (cap.contains('WPA')) return 'Weak';
    if (cap.contains('WEP')) return 'Weak';
    return 'Open';
  }

  static String securityTag(String capabilities) {
    final cap = capabilities.toUpperCase();
    if (cap.contains('WPA3')) return 'WPA3';
    if (cap.contains('WPA2-EAP') || cap.contains('Enterprise')) return 'WPA2-Ent';
    if (cap.contains('WPA2') || cap.contains('RSN')) return 'WPA2';
    if (cap.contains('WPA')) return 'WPA';
    if (cap.contains('WEP')) return 'WEP';
    return 'Open';
  }

  static String riskDescription(String classification) {
    switch (classification) {
      case 'Open':
        return 'This network has NO encryption. Anyone nearby can intercept all your traffic. Avoid using it for sensitive data. If this is your network, log into your router and enable WPA3 or WPA2-AES immediately.';
      case 'Weak':
        return 'WEP and WPA-TKIP are broken encryption standards. They can be cracked in minutes. Upgrade to WPA2-AES or WPA3 via your router admin panel (typically 192.168.1.1 or 192.168.0.1).';
      case 'Caution':
        return 'WPA2-PSK is widely used and generally safe, but vulnerable to offline dictionary attacks if you use a weak password. Use a 12+ character random password. Consider upgrading to WPA3 if your router supports it.';
      case 'Strong':
        return 'This network uses strong encryption (WPA3 or WPA2-Enterprise). No immediate action required. Keep your router firmware updated.';
      default:
        return 'Unable to determine security level.';
    }
  }
}

/// PDR (Pedestrian Dead Reckoning) position tracker
class PDREngine {
  double x = 0.0;
  double y = 0.0;
  double headingRad = 0.0;
  double strideLengthM;
  int stepCount = 0;

  PDREngine({this.strideLengthM = 0.75});

  void updateHeading(double radians) {
    headingRad = radians;
  }

  /// Call on each step detector event
  ({double x, double y}) onStep() {
    stepCount++;
    x += strideLengthM * sin(headingRad);
    y += strideLengthM * cos(headingRad);
    return (x: x, y: y);
  }

  void reset() {
    x = 0.0;
    y = 0.0;
    stepCount = 0;
  }
}

/// Bilinear interpolation heatmap generator
class HeatmapInterpolator {
  static List<List<double>> interpolate(
    List<({double x, double y, double rssi})> points,
    int gridSize,
    double minX,
    double maxX,
    double minY,
    double maxY,
  ) {
    final grid = List.generate(
      gridSize,
      (_) => List.filled(gridSize, double.nan),
    );

    if (points.isEmpty) return grid;

    final rangeX = maxX - minX;
    final rangeY = maxY - minY;
    if (rangeX == 0 || rangeY == 0) return grid;

    for (int row = 0; row < gridSize; row++) {
      for (int col = 0; col < gridSize; col++) {
        final gx = minX + rangeX * col / (gridSize - 1);
        final gy = minY + rangeY * row / (gridSize - 1);

        // Inverse distance weighting
        double weightSum = 0;
        double valueSum = 0;
        for (final p in points) {
          final d = sqrt(pow(gx - p.x, 2) + pow(gy - p.y, 2));
          if (d < 0.01) {
            valueSum = p.rssi;
            weightSum = 1.0;
            break;
          }
          final w = 1.0 / pow(d, 2);
          weightSum += w;
          valueSum += w * p.rssi;
        }
        grid[row][col] = weightSum > 0 ? valueSum / weightSum : -90.0;
      }
    }
    return grid;
  }
}

/// ITU indoor path-loss model
/// L(dBm) = 20*log10(f_MHz) + N*log10(d_m) + Lf(n) - 28
double ituPathLoss({
  required double frequencyMHz,
  required double distanceM,
  double n = 28.0,
  double floorAttenuation = 0.0,
}) {
  if (distanceM <= 0) distanceM = 0.1;
  return 20 * log(frequencyMHz) / ln10 +
      n * log(distanceM) / ln10 +
      floorAttenuation -
      28;
}

double estimateRssi({
  required double txPowerDbm,
  required double frequencyMHz,
  required double distanceM,
  double n = 28.0,
}) {
  return txPowerDbm - ituPathLoss(frequencyMHz: frequencyMHz, distanceM: distanceM, n: n);
}

/// Trilateration engine for AR router positioning
class TrilaterationEngine {
  /// Estimates the router position using least squares gradient descent.
  /// Needs at least 4 measurements.
  static ({double x, double y, double z})? estimatePosition(
      List<({double x, double y, double z, double rssi, double freq})> measurements,
      {int iterations = 100, double learningRate = 0.05}) {
    if (measurements.length < 4) return null;

    // Initial guess: average of positions
    double px = 0, py = 0, pz = 0;
    for (var m in measurements) {
      px += m.x; py += m.y; pz += m.z;
    }
    px /= measurements.length;
    py /= measurements.length;
    pz /= measurements.length;

    // Convert RSSI to estimated distance for each measurement
    List<double> targetDistances = measurements.map((m) {
      // rough txPower ~ -30 dBm
      double txPower = -30.0;
      double logDist = (txPower - m.rssi - 20 * log(m.freq) / ln10 + 28) / 28.0;
      return pow(10, logDist).toDouble();
    }).toList();

    for (int iter = 0; iter < iterations; iter++) {
      double gradX = 0, gradY = 0, gradZ = 0;

      for (int i = 0; i < measurements.length; i++) {
        var m = measurements[i];
        double dTarget = targetDistances[i];
        double dx = px - m.x;
        double dy = py - m.y;
        double dz = pz - m.z;
        double dCalc = sqrt(dx * dx + dy * dy + dz * dz);
        
        if (dCalc == 0) continue;

        double error = dCalc - dTarget;
        
        gradX += 2 * error * (dx / dCalc);
        gradY += 2 * error * (dy / dCalc);
        gradZ += 2 * error * (dz / dCalc);
      }

      px -= learningRate * gradX / measurements.length;
      py -= learningRate * gradY / measurements.length;
      pz -= learningRate * gradZ / measurements.length;
    }

    return (x: px, y: py, z: pz);
  }
}

/// AI Router Placement advisor
class AIRouterPlacement {
  /// Brute-force search over a discrete grid to find the optimal router position
  /// that maximizes the coverage score (percentage of cells > targetRssiDbm).
  static ({double x, double y, double coveragePercent}) optimizePlacement({
    required double minX,
    required double maxX,
    required double minY,
    required double maxY,
    required double txPowerDbm,
    required double frequencyMHz,
    double gridResolutionM = 0.5,
    double targetRssiDbm = -70.0,
  }) {
    double bestX = minX;
    double bestY = minY;
    double maxCoverage = -1.0;

    int cols = ((maxX - minX) / gridResolutionM).ceil();
    int rows = ((maxY - minY) / gridResolutionM).ceil();
    
    if (cols <= 0 || rows <= 0) {
      return (x: minX, y: minY, coveragePercent: 0.0);
    }

    for (int rX = 0; rX <= cols; rX++) {
      for (int rY = 0; rY <= rows; rY++) {
        double routerX = minX + rX * gridResolutionM;
        double routerY = minY + rY * gridResolutionM;

        int totalCells = 0;
        int coveredCells = 0;

        for (int cX = 0; cX <= cols; cX++) {
          for (int cY = 0; cY <= rows; cY++) {
            double cellX = minX + cX * gridResolutionM;
            double cellY = minY + cY * gridResolutionM;

            double dist = sqrt(pow(routerX - cellX, 2) + pow(routerY - cellY, 2));
            if (dist < 0.1) dist = 0.1;

            double predictedRssi = estimateRssi(
              txPowerDbm: txPowerDbm,
              frequencyMHz: frequencyMHz,
              distanceM: dist,
            );

            totalCells++;
            if (predictedRssi >= targetRssiDbm) {
              coveredCells++;
            }
          }
        }

        double coverage = (coveredCells / totalCells) * 100.0;
        if (coverage > maxCoverage) {
          maxCoverage = coverage;
          bestX = routerX;
          bestY = routerY;
        }
      }
    }

    return (x: bestX, y: bestY, coveragePercent: maxCoverage);
  }
}
