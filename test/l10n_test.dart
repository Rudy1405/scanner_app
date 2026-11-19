import 'dart:ui';

import 'package:escaner_local/l10n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('language follows the device and falls back to Spanish', () {
    expect(resolveLang([const Locale('en', 'US')]), 'en');
    expect(resolveLang([const Locale('de'), const Locale('fr')]), 'fr');
    expect(resolveLang([const Locale('de')]), 'es');
    expect(resolveLang([]), 'es');
  });

  test('translations, placeholders and plurals', () {
    setLang('es');
    expect(t('Cancelar'), 'Cancelar');
    expect(t('Página {n} de {total}', {'n': 2, 'total': 5}), 'Página 2 de 5');
    setLang('en');
    expect(t('Cancelar'), 'Cancel');
    expect(t('Página {n} de {total}', {'n': 2, 'total': 5}), 'Page 2 of 5');
    expect(plural(1, 'página', 'páginas'), 'page');
    expect(plural(3, 'página', 'páginas'), 'pages');
    expect(t('texto sin traducir'), 'texto sin traducir');
    setLang('fr');
    expect(t('Guardar'), 'Enregistrer');
    setLang('pt');
    expect(t('Guardar'), 'Salvar');
  });
}
