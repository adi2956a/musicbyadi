import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SearchBarInline extends StatefulWidget {
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;
  final String hintText;

  const SearchBarInline({
    Key? key,
    required this.onChanged,
    this.onClear,
    this.hintText = 'Search library...',
  }) : super(key: key);

  @override
  State<SearchBarInline> createState() => _SearchBarInlineState();
}

class _SearchBarInlineState extends State<SearchBarInline> {
  final TextEditingController _controller = TextEditingController();
  bool _expanded = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      return IconButton(
        icon: const Icon(Icons.search, color: AppColors.textPrimary, size: 22),
        splashRadius: 20,
        onPressed: () {
          setState(() {
            _expanded = true;
          });
        },
      );
    }

    return Container(
      width: 220,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: AppColors.divider),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          const Icon(Icons.search, color: AppColors.textSecondary, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: const TextStyle(color: AppColors.textDisabled, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: widget.onChanged,
            ),
          ),
          GestureDetector(
            onTap: () {
              _controller.clear();
              widget.onChanged('');
              widget.onClear?.call();
              setState(() {
                _expanded = false;
              });
            },
            child: const Icon(Icons.close, color: AppColors.textSecondary, size: 16),
          ),
        ],
      ),
    );
  }
}
