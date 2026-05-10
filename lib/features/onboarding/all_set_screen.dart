import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/demo/demo_library.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/artwork.dart';

class AllSetScreen extends ConsumerStatefulWidget {
  const AllSetScreen({super.key});

  @override
  ConsumerState<AllSetScreen> createState() => _AllSetScreenState();
}

class _AllSetScreenState extends ConsumerState<AllSetScreen>
    with TickerProviderStateMixin {
  late final AnimationController _stagger = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..forward();

  @override
  void dispose() {
    _stagger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final library = DemoLibrary.albums.take(9).toList();
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.gutterGenerous,
            vertical: AfSpacing.s24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'You’re all set',
                style: AfTypography.display.copyWith(
                  color: AfColors.textPrimary,
                ),
              ),
              const SizedBox(height: AfSpacing.s8),
              Text(
                auth == null
                    ? 'Demo library loaded. You can connect a Jellyfin '
                        'server later from Settings.'
                    : 'Connected to ${auth.server.name}. Your library is '
                        'ready.',
                style: AfTypography.bodyLarge.copyWith(
                  color: AfColors.textSecondary,
                ),
              ),
              const SizedBox(height: AfSpacing.s24),
              _StatRow(),
              const SizedBox(height: AfSpacing.s24),
              Expanded(
                child: GridView.builder(
                  itemCount: 9,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemBuilder: (context, i) {
                    final delay = (i * 40) / 600.0;
                    return AnimatedBuilder(
                      animation: _stagger,
                      builder: (context, _) {
                        final t = ((_stagger.value - delay) / 0.27)
                            .clamp(0.0, 1.0);
                        return Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset(0, (1 - t) * 8),
                            child: Artwork(
                              url: library[i].imageUrl,
                              size: double.infinity,
                              height: double.infinity,
                              radius: AfRadii.borderMd,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: AfSpacing.s24),
              ElevatedButton(
                onPressed: () => context.go('/home'),
                child: const Text('Start listening'),
              ),
              const SizedBox(height: AfSpacing.s24),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tracks = DemoLibrary.tracks.length;
    final albums = DemoLibrary.albums.length;
    final hours = (DemoLibrary.tracks.fold<int>(
                0, (sum, t) => sum + t.duration.inMinutes) /
            60)
        .round();
    return Row(
      children: [
        _Stat(label: 'Tracks', value: '$tracks'),
        _Stat(label: 'Albums', value: '$albums'),
        _Stat(label: 'Hours', value: '$hours'),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: AfSpacing.s16,
          horizontal: AfSpacing.s12,
        ),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: AfColors.surfaceBase,
          borderRadius: AfRadii.borderMd,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: AfTypography.titleLarge),
            const SizedBox(height: 2),
            Text(
              label,
              style: AfTypography.bodySmall.copyWith(
                color: AfColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
