import 'package:flutter/material.dart';
import 'tokens.dart';

class BestieLogo extends StatelessWidget {
  final double size;
  final bool withWordmark;
  const BestieLogo({super.key, this.size = 40, this.withWordmark = false});

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.25),
        boxShadow: [
          BoxShadow(
            color: BestieTokens.cBrand.withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/branding/app_icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          decoration: BoxDecoration(
            gradient: BestieTokens.gBrand,
            borderRadius: BorderRadius.circular(size * 0.25),
          ),
          child: Icon(Icons.campaign_rounded, color: Colors.white, size: size * 0.52),
        ),
      ),
    );

    if (!withWordmark) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(width: size * 0.28),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (rect) => BestieTokens.gBrand.createShader(rect),
              child: Text(
                'Marketing',
                style: TextStyle(
                  fontSize: size * 0.38,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            Text(
              'Executives',
              style: TextStyle(
                fontSize: size * 0.22,
                fontWeight: FontWeight.w600,
                color: BestieTokens.cTextMuted,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class BestiePrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  const BestiePrimaryButton({super.key, required this.label, this.onPressed, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(label),
      ),
    );
  }
}

class BestieTextField extends StatefulWidget {
  final String label;
  final TextEditingController? controller;
  final IconData? icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final void Function(String)? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;

  const BestieTextField({
    super.key,
    required this.label,
    this.controller,
    this.icon,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  State<BestieTextField> createState() => _BestieTextFieldState();
}

class _BestieTextFieldState extends State<BestieTextField> {
  late bool _obscured = widget.obscure;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(fontSize: 13, fontWeight: BestieTokens.fwSemibold, color: BestieTokens.cTextSoft),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          obscureText: _obscured,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          onSubmitted: widget.onSubmitted,
          autofocus: widget.autofocus,
          decoration: InputDecoration(
            prefixIcon: widget.icon != null
                ? Icon(widget.icon, size: 18, color: BestieTokens.cTextMuted)
                : null,
            suffixIcon: widget.obscure
                ? IconButton(
                    icon: Icon(
                      _obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 20,
                      color: BestieTokens.cTextMuted,
                    ),
                    onPressed: () => setState(() => _obscured = !_obscured),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

class BestieLoginBackdrop extends StatelessWidget {
  const BestieLoginBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: BestieTokens.gLoginBackdrop),
      child: Stack(
        children: [
          Positioned(top: -90, left: -60, child: _glow(220)),
          Positioned(bottom: -120, right: -80, child: _glow(300)),
        ],
      ),
    );
  }

  Widget _glow(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [Colors.white.withValues(alpha: 0.22), Colors.transparent]),
        ),
      );
}

class BestieErrorBanner extends StatelessWidget {
  final String message;
  const BestieErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: BestieTokens.cDangerSoft,
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
        border: Border.all(color: BestieTokens.cDanger.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: BestieTokens.cDanger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: BestieTokens.cDanger, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class BestieGradientHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const BestieGradientHeader({super.key, required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(BestieTokens.s4),
      decoration: BoxDecoration(
        gradient: BestieTokens.gBrand,
        borderRadius: BorderRadius.circular(BestieTokens.rLg),
        boxShadow: [
          BoxShadow(
            color: BestieTokens.cBrand.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (trailing != null) trailing!,
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: BestieTokens.fwSemibold)),
          const SizedBox(height: 6),
          Text(
            subtitle ?? title,
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: BestieTokens.fwBold),
          ),
        ],
      ),
    );
  }
}

class BestieStatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? accent;
  const BestieStatTile({super.key, required this.label, required this.value, required this.icon, this.accent});

  @override
  Widget build(BuildContext context) {
    final color = accent ?? BestieTokens.cBrand;
    return Container(
      padding: const EdgeInsets.all(BestieTokens.s3),
      decoration: BoxDecoration(
        color: BestieTokens.cSurface,
        borderRadius: BorderRadius.circular(BestieTokens.rLg),
        border: Border.all(color: BestieTokens.cBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: BestieTokens.fwBold, color: BestieTokens.cText)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: BestieTokens.cTextMuted)),
        ],
      ),
    );
  }
}

class BestieSectionTitle extends StatelessWidget {
  final String title;
  final Widget? action;
  const BestieSectionTitle({super.key, required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(BestieTokens.s3, BestieTokens.s3, BestieTokens.s3, BestieTokens.s1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: BestieTokens.fwBold,
                letterSpacing: 0.8,
                color: BestieTokens.cTextMuted,
              ),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class BestieShellAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final List<Widget>? actions;
  final bool showLogo;
  const BestieShellAppBar({super.key, this.title, this.actions, this.showLogo = true});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: showLogo
          ? const BestieLogo(size: 28, withWordmark: true)
          : Text(title ?? '', style: const TextStyle(fontWeight: BestieTokens.fwBold)),
      actions: actions,
    );
  }
}
