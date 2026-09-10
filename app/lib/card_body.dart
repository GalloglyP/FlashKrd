import 'dart:io';

import 'package:flashkrd/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:path/path.dart' as p;

class CardBody extends StatelessWidget {
  const CardBody({
    super.key,
    required this.text,
    required this.store,
    required this.deckId,
  });

  final String text;
  final Store store;
  final String deckId;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
          fontSize: 22,
          height: 1.45,
          color: Colors.black,
        );
    final parts = _splitMath(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final part in parts)
          if (part.math)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _math(part.text, part.display, style),
            )
          else
            MarkdownBody(
              data: part.text,
              selectable: false,
              styleSheet: MarkdownStyleSheet(
                p: style,
                h1: style?.copyWith(fontSize: 28, fontWeight: FontWeight.w700),
                h2: style?.copyWith(fontSize: 24, fontWeight: FontWeight.w700),
                code: style?.copyWith(fontFamily: 'monospace', fontSize: 18),
              ),
              sizedImageBuilder: (config) {
                final file = File(
                  p.normalize(store.mediaFile(deckId, config.uri.path).path),
                );
                if (!file.existsSync()) {
                  return Text(config.alt ?? config.uri.toString(), style: style);
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Image.file(file),
                );
              },
            ),
      ],
    );
  }
}

class _Part {
  const _Part(this.text, {required this.math, this.display = false});
  final String text;
  final bool math;
  final bool display;
}

Widget _math(String tex, bool display, TextStyle? style) {
  try {
    return Math.tex(
      tex,
      mathStyle: display ? MathStyle.display : MathStyle.text,
      textStyle: style,
    );
  } catch (_) {
    return Text(tex, style: style);
  }
}

List<_Part> _splitMath(String source) {
  final pattern = RegExp(r'\$\$([\s\S]+?)\$\$|\$([^\$]+)\$');
  final out = <_Part>[];
  var start = 0;
  for (final match in pattern.allMatches(source)) {
    if (match.start > start) {
      out.add(_Part(source.substring(start, match.start), math: false));
    }
    if (match.group(1) != null) {
      out.add(_Part(match.group(1)!.trim(), math: true, display: true));
    } else {
      out.add(_Part(match.group(2)!.trim(), math: true));
    }
    start = match.end;
  }
  if (start < source.length) {
    out.add(_Part(source.substring(start), math: false));
  }
  return out.isEmpty ? const [_Part('', math: false)] : out;
}
