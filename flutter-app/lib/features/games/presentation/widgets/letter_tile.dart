import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// A tappable letter tile for the Word Scramble game.
///
/// Changes color to indicate correct or wrong state.
class LetterTile extends StatefulWidget {
  final String letter;
  final bool isSelected;
  final bool isCorrect;
  final bool isWrong;
  final VoidCallback? onTap;

  const LetterTile({
    super.key,
    required this.letter,
    this.isSelected = false,
    this.isCorrect = false,
    this.isWrong = false,
    this.onTap,
  });

  @override
  State<LetterTile> createState() => _LetterTileState();
}

class _LetterTileState extends State<LetterTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -6), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -6, end: 6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6, end: -4), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -4, end: 4), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 4, end: 0), weight: 1),
    ]).animate(_shakeController);
  }

  @override
  void didUpdateWidget(LetterTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isWrong && widget.isWrong) {
      _shakeController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Color get _tileColor {
    if (widget.isCorrect) return AppColors.greenSuccess;
    if (widget.isWrong) return const Color(0xFFC62828);
    if (widget.isSelected) return AppColors.primary;
    return Colors.white;
  }

  Color get _textColor {
    if (widget.isCorrect || widget.isWrong || widget.isSelected) {
      return Colors.white;
    }
    return AppColors.textDark;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_shakeAnimation.value, 0),
          child: child,
        );
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 42,
          height: 48,
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: _tileColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.isSelected
                  ? AppColors.primary.withOpacity(0.6)
                  : AppColors.grey300,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _tileColor.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            widget.letter.toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: _textColor,
            ),
          ),
        ),
      ),
    );
  }
}
