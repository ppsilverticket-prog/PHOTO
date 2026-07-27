/// 파라메트릭 필터 프리셋.
///
/// LUT 텍스처 대신 (기본 보정값 + 채널별 lift/gamma/gain) 조합으로 룩을
/// 정의한다. GPU 셰이더와 CPU 저장 경로가 같은 파라미터를 공유하므로
/// 프리뷰와 결과물이 항상 일치한다.
class FilterPreset {
  const FilterPreset({
    required this.id,
    required this.name,
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.temperature = 0,
    this.tint = 0,
    this.lift = const [0, 0, 0],
    this.gamma = const [1, 1, 1],
    this.gain = const [1, 1, 1],
  });

  final String id;
  final String name;
  final double brightness;
  final double contrast;
  final double saturation;
  final double temperature;
  final double tint;

  /// 채널별(R, G, B) 값.
  final List<double> lift;
  final List<double> gamma;
  final List<double> gain;
}

/// 기본 제공 필터 19종 ("원본"은 preset == null 로 표현).
const List<FilterPreset> kFilterPresets = [
  FilterPreset(
    id: 'clear',
    name: '청아',
    brightness: 0.06,
    contrast: 0.05,
    saturation: 0.08,
    temperature: -0.08,
    gamma: [1.03, 1.03, 1.03],
  ),
  FilterPreset(
    id: 'film',
    name: '필름',
    contrast: -0.05,
    saturation: -0.12,
    lift: [0.04, 0.03, 0.02],
    gamma: [1.02, 1.0, 0.98],
    gain: [0.98, 0.99, 1.0],
  ),
  FilterPreset(
    id: 'vintage',
    name: '빈티지',
    temperature: 0.15,
    saturation: -0.2,
    lift: [0.06, 0.04, 0.02],
    gain: [0.97, 0.95, 0.9],
  ),
  FilterPreset(
    id: 'sepia',
    name: '세피아',
    saturation: -0.85,
    temperature: 0.3,
    tint: 0.05,
    lift: [0.08, 0.05, 0.01],
    gain: [1.0, 0.92, 0.78],
  ),
  FilterPreset(
    id: 'mono',
    name: '모노',
    saturation: -1,
    contrast: 0.08,
  ),
  FilterPreset(
    id: 'noir',
    name: '느와르',
    saturation: -1,
    contrast: 0.3,
    lift: [-0.03, -0.03, -0.03],
    gain: [1.05, 1.05, 1.05],
  ),
  FilterPreset(
    id: 'cinema',
    name: '시네마',
    contrast: 0.12,
    saturation: -0.05,
    temperature: -0.05,
    lift: [0.0, 0.01, 0.02],
    gain: [1.0, 0.98, 0.95],
  ),
  FilterPreset(
    id: 'teal_orange',
    name: '틸오렌지',
    temperature: 0.12,
    contrast: 0.1,
    lift: [-0.02, 0.01, 0.03],
    gain: [1.05, 0.98, 0.92],
  ),
  FilterPreset(
    id: 'cozy',
    name: '포근',
    temperature: 0.18,
    brightness: 0.05,
    saturation: 0.05,
    gamma: [1.05, 1.05, 1.05],
  ),
  FilterPreset(
    id: 'dawn',
    name: '새벽',
    temperature: -0.18,
    tint: 0.04,
    brightness: 0.03,
    saturation: -0.08,
    lift: [0.02, 0.03, 0.06],
  ),
  FilterPreset(
    id: 'sunset',
    name: '노을',
    temperature: 0.25,
    tint: 0.06,
    saturation: 0.12,
    gain: [1.05, 0.95, 0.85],
  ),
  FilterPreset(
    id: 'mint',
    name: '민트',
    temperature: -0.12,
    tint: 0.08,
    gain: [0.95, 1.02, 1.0],
  ),
  FilterPreset(
    id: 'lavender',
    name: '라벤더',
    temperature: -0.05,
    tint: -0.1,
    lift: [0.04, 0.02, 0.06],
  ),
  FilterPreset(
    id: 'rose',
    name: '로즈',
    temperature: 0.08,
    tint: -0.08,
    brightness: 0.04,
    lift: [0.05, 0.02, 0.03],
  ),
  FilterPreset(
    id: 'cafe',
    name: '카페',
    temperature: 0.15,
    saturation: -0.15,
    contrast: 0.08,
    gain: [0.98, 0.93, 0.85],
  ),
  FilterPreset(
    id: 'forest',
    name: '숲',
    temperature: -0.05,
    tint: 0.1,
    saturation: 0.1,
    gamma: [1.0, 1.04, 1.0],
  ),
  FilterPreset(
    id: 'ocean',
    name: '바다',
    temperature: -0.15,
    saturation: 0.08,
    contrast: 0.06,
    gain: [0.92, 0.98, 1.06],
  ),
  FilterPreset(
    id: 'neon',
    name: '네온',
    saturation: 0.3,
    contrast: 0.2,
    brightness: 0.02,
  ),
  FilterPreset(
    id: 'fade',
    name: '페이드',
    contrast: -0.18,
    saturation: -0.1,
    lift: [0.08, 0.08, 0.08],
    gain: [0.95, 0.95, 0.95],
  ),
];

FilterPreset? filterPresetById(String? id) {
  if (id == null) return null;
  for (final preset in kFilterPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}
