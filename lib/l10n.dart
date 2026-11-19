// Translations. The Spanish text is the key, so Spanish needs no entry and any
// missing translation falls back to Spanish (the default language).
//
// To add a language: add its code to [supportedLangs], then add one more value
// at the end of every row in [_tr] (order: en, pt, fr, <new>).
import 'dart:ui' as ui;

const supportedLangs = ['es', 'en', 'pt', 'fr'];
const _order = ['en', 'pt', 'fr'];

String _lang = 'es';

/// Current language code (es, en, pt, fr).
String get lang => _lang;

/// Picks the device language when we have it, Spanish otherwise.
String resolveLang(List<ui.Locale> locales) {
  for (final l in locales) {
    if (supportedLangs.contains(l.languageCode)) return l.languageCode;
  }
  return 'es';
}

void setLang(String code) => _lang = supportedLangs.contains(code) ? code : 'es';

/// Translates [es] and fills `{name}` placeholders from [args].
String t(String es, [Map<String, Object?>? args]) {
  var out = es;
  if (_lang != 'es') {
    final row = _tr[es];
    final i = _order.indexOf(_lang);
    if (row != null && i >= 0 && i < row.length) out = row[i];
  }
  if (args != null) {
    args.forEach((k, v) => out = out.replaceAll('{$k}', '$v'));
  }
  return out;
}

/// 1 / many form of a word: `plural(n, 'página', 'páginas')`.
String plural(int n, String one, String many) => t(n == 1 ? one : many);

/// Decimal separator for numbers shown to the user.
String get decimalSep => _lang == 'en' ? '.' : ',';

List<String> get monthsShort => switch (_lang) {
      'en' => const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
      'pt' => const ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'],
      'fr' => const ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'],
      _ => const ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'],
    };

// es → [en, pt, fr]
const Map<String, List<String>> _tr = {
  // Home
  'Mis documentos': ['My documents', 'Meus documentos', 'Mes documents'],
  'Buscar por nombre o texto': ['Search by name or text', 'Buscar por nome ou texto', 'Rechercher par nom ou texte'],
  'Resultados': ['Results', 'Resultados', 'Résultats'],
  'Recientes': ['Recent', 'Recentes', 'Récents'],
  'resultado': ['result', 'resultado', 'résultat'],
  'resultados': ['results', 'resultados', 'résultats'],
  'documento': ['document', 'documento', 'document'],
  'documentos': ['documents', 'documentos', 'documents'],
  'página': ['page', 'página', 'page'],
  'páginas': ['pages', 'páginas', 'pages'],
  'Hoy': ['Today', 'Hoje', "Aujourd'hui"],
  'Ayer': ['Yesterday', 'Ontem', 'Hier'],
  'Ver como lista': ['View as list', 'Ver como lista', 'Afficher en liste'],
  'Ver como cuadrícula': ['View as grid', 'Ver como grade', 'Afficher en grille'],
  'Ajustes': ['Settings', 'Ajustes', 'Réglages'],
  'Nada coincide con la búsqueda': ['Nothing matches your search', 'Nada corresponde à busca', 'Aucun résultat pour la recherche'],
  'Escanea tu primer documento': ['Scan your first document', 'Escaneie seu primeiro documento', 'Numérisez votre premier document'],
  'Apunta la cámara a una hoja: detectamos los bordes y la dejamos lista como PDF.': [
    'Point the camera at a sheet: we detect the edges and get it ready as a PDF.',
    'Aponte a câmera para uma folha: detectamos as bordas e deixamos pronta como PDF.',
    'Pointez la caméra vers une feuille : nous détectons les bords et la préparons en PDF.'
  ],
  'Escanear documento': ['Scan document', 'Escanear documento', 'Numériser un document'],
  'Importar de la galería': ['Import from gallery', 'Importar da galeria', 'Importer depuis la galerie'],
  'Importar imágenes': ['Import images', 'Importar imagens', 'Importer des images'],
  'Más opciones de {name}': ['More options for {name}', 'Mais opções de {name}', 'Plus d’options pour {name}'],
  'Sin anuncios · Sin nube · Todo queda en tu {device}': [
    'No ads · No cloud · Everything stays on your {device}',
    'Sem anúncios · Sem nuvem · Tudo fica no seu {device}',
    'Sans pub · Sans cloud · Tout reste sur votre {device}'
  ],
  'teléfono': ['phone', 'celular', 'téléphone'],

  // Dialogs / common
  'Cambiar nombre': ['Rename', 'Renomear', 'Renommer'],
  'Compartir PDF': ['Share PDF', 'Compartilhar PDF', 'Partager le PDF'],
  'Eliminar': ['Delete', 'Excluir', 'Supprimer'],
  'Cancelar': ['Cancel', 'Cancelar', 'Annuler'],
  'Guardar': ['Save', 'Salvar', 'Enregistrer'],
  'Cerrar': ['Close', 'Fechar', 'Fermer'],
  'Volver': ['Back', 'Voltar', 'Retour'],
  'Compartir': ['Share', 'Compartilhar', 'Partager'],
  'Creando PDF…': ['Creating PDF…', 'Criando PDF…', 'Création du PDF…'],
  'Guardando…': ['Saving…', 'Salvando…', 'Enregistrement…'],
  'Girando…': ['Rotating…', 'Girando…', 'Rotation…'],
  '¿Eliminar «{name}»?': ['Delete “{name}”?', 'Excluir “{name}”?', 'Supprimer « {name} » ?'],
  'Se borrará de este {device} y no se puede deshacer.': [
    'It will be removed from this {device} and can’t be undone.',
    'Será apagado deste {device} e não pode ser desfeito.',
    'Il sera supprimé de ce {device} et c’est irréversible.'
  ],
  'No se puede deshacer.': ['This can’t be undone.', 'Não pode ser desfeito.', 'Action irréversible.'],
  'Escribe un nombre para este documento.': ['Type a name for this document.', 'Digite um nome para este documento.', 'Saisissez un nom pour ce document.'],

  // Settings
  'Filtro por defecto': ['Default filter', 'Filtro padrão', 'Filtre par défaut'],
  'Escaneo': ['Scanning', 'Escaneamento', 'Numérisation'],
  'Detectar bordes automáticamente': ['Detect edges automatically', 'Detectar bordas automaticamente', 'Détecter les bords automatiquement'],
  'Recorta la hoja sola; luego puedes ajustarla.': [
    'Crops the sheet on its own; you can adjust it afterwards.',
    'Recorta a folha sozinho; depois você pode ajustar.',
    'Recadre la feuille seul ; vous pourrez l’ajuster ensuite.'
  ],
  'Captura automática': ['Auto capture', 'Captura automática', 'Capture automatique'],
  'Hace la foto cuando la hoja está quieta.': [
    'Takes the photo when the sheet is still.',
    'Tira a foto quando a folha está parada.',
    'Prend la photo quand la feuille est immobile.'
  ],
  'PDF e imágenes': ['PDF & images', 'PDF e imagens', 'PDF et images'],
  'Tamaño de página': ['Page size', 'Tamanho da página', 'Taille de page'],
  'Carta': ['Letter', 'Carta', 'Letter'],
  'Ajustar': ['Fit', 'Ajustar', 'Ajuster'],
  'Ajustar a la imagen': ['Fit to image', 'Ajustar à imagem', 'Ajuster à l’image'],
  'Calidad': ['Quality', 'Qualidade', 'Qualité'],
  'Privacidad': ['Privacy', 'Privacidade', 'Confidentialité'],
  'Todo se guarda en este dispositivo': [
    'Everything is stored on this device',
    'Tudo é salvo neste dispositivo',
    'Tout est enregistré sur cet appareil'
  ],
  'Ruta copiada': ['Path copied', 'Caminho copiado', 'Chemin copié'],
  'Privado en esta app': ['Private in this app', 'Privado neste app', 'Privé dans cette app'],
  'Calculando…': ['Calculating…', 'Calculando…', 'Calcul…'],
  'menos de 1 MB': ['under 1 MB', 'menos de 1 MB', 'moins de 1 Mo'],
  'Escáner Local 1.0\nSin anuncios · Sin cuentas · Sin nube': [
    'Escáner Local 1.0\nNo ads · No accounts · No cloud',
    'Escáner Local 1.0\nSem anúncios · Sem contas · Sem nuvem',
    'Escáner Local 1.0\nSans pub · Sans compte · Sans cloud'
  ],
  'Apariencia': ['Appearance', 'Aparência', 'Apparence'],

  // Text recognition
  'El reconocimiento de texto funciona en Android y iPhone.': [
    'Text recognition works on Android and iPhone.',
    'O reconhecimento de texto funciona no Android e iPhone.',
    'La reconnaissance de texte fonctionne sur Android et iPhone.'
  ],
  'Reconociendo texto…': ['Recognizing text…', 'Reconhecendo texto…', 'Reconnaissance du texte…'],
  'Copiar texto': ['Copy text', 'Copiar texto', 'Copier le texte'],
  'Copiado': ['Copied', 'Copiado', 'Copié'],
  'Compartir texto': ['Share text', 'Compartilhar texto', 'Partager le texte'],
  'Texto': ['Text', 'Texto', 'Texte'],
  'Aún no se ha reconocido el texto': ['Text hasn’t been recognized yet', 'O texto ainda não foi reconhecido', 'Le texte n’a pas encore été reconnu'],
  'Reconocer texto': ['Recognize text', 'Reconhecer texto', 'Reconnaître le texte'],
  'Volver a reconocer': ['Recognize again', 'Reconhecer novamente', 'Reconnaître à nouveau'],
  'Se hace en el propio dispositivo, sin internet.': [
    'Done on the device itself, no internet.',
    'Feito no próprio dispositivo, sem internet.',
    'Effectué sur l’appareil, sans internet.'
  ],

  // Document
  'PDF guardado': ['PDF saved', 'PDF salvo', 'PDF enregistré'],
  'Imágenes guardadas': ['Images saved', 'Imagens salvas', 'Images enregistrées'],
  'Guardar PDF en Archivos': ['Save PDF to Files', 'Salvar PDF em Arquivos', 'Enregistrer le PDF dans Fichiers'],
  'Exportar JPG': ['Export JPG', 'Exportar JPG', 'Exporter en JPG'],
  'Eliminar documento': ['Delete document', 'Excluir documento', 'Supprimer le document'],
  'Documentos': ['Documents', 'Documentos', 'Documents'],
  'Ordenar páginas': ['Reorder pages', 'Reordenar páginas', 'Réorganiser les pages'],
  'Más opciones': ['More options', 'Mais opções', 'Plus d’options'],
  'Cambiar nombre: {name}': ['Rename: {name}', 'Renomear: {name}', 'Renommer : {name}'],
  'Añadir': ['Add', 'Adicionar', 'Ajouter'],
  'Añadir páginas': ['Add pages', 'Adicionar páginas', 'Ajouter des pages'],
  'Listo': ['Done', 'Concluído', 'Terminé'],
  'MANTÉN PULSADO Y ARRASTRA PARA REORDENAR': [
    'PRESS AND HOLD, THEN DRAG TO REORDER',
    'SEGURE E ARRASTE PARA REORDENAR',
    'APPUYEZ LONGUEMENT ET FAITES GLISSER POUR RÉORGANISER'
  ],
  'El orden se usa al exportar el PDF.': ['The order is used when exporting the PDF.', 'A ordem é usada ao exportar o PDF.', 'L’ordre est utilisé lors de l’export du PDF.'],
  'Quitar página {n}': ['Remove page {n}', 'Remover página {n}', 'Retirer la page {n}'],
  'Página {n}': ['Page {n}', 'Página {n}', 'Page {n}'],
  'Filtro: {name}': ['Filter: {name}', 'Filtro: {name}', 'Filtre : {name}'],
  '¿Eliminar la página {n}?': ['Delete page {n}?', 'Excluir a página {n}?', 'Supprimer la page {n} ?'],
  'Desliza para cambiar de página · Pellizca para ampliar': [
    'Swipe to change page · Pinch to zoom',
    'Deslize para trocar de página · Pince para ampliar',
    'Balayez pour changer de page · Pincez pour zoomer'
  ],
  'Recortar': ['Crop', 'Recortar', 'Recadrer'],
  'Filtro': ['Filter', 'Filtro', 'Filtre'],
  'Girar': ['Rotate', 'Girar', 'Pivoter'],
  'Original': ['Original', 'Original', 'Original'],
  'Mejorar': ['Enhance', 'Melhorar', 'Améliorer'],
  'Aclarar': ['Lighten', 'Clarear', 'Éclaircir'],
  'Grises': ['Grayscale', 'Cinza', 'Gris'],
  'B/N': ['B/W', 'P/B', 'N/B'],

  // Scan flow
  'Nuevo documento': ['New document', 'Novo documento', 'Nouveau document'],
  'Escanear con la cámara': ['Scan with the camera', 'Escanear com a câmera', 'Numériser avec la caméra'],
  'Varias páginas seguidas, bordes automáticos': [
    'Several pages in a row, automatic edges',
    'Várias páginas seguidas, bordas automáticas',
    'Plusieurs pages à la suite, bords automatiques'
  ],
  'Elige una o varias fotos de tu galería': [
    'Pick one or more photos from your gallery',
    'Escolha uma ou várias fotos da sua galeria',
    'Choisissez une ou plusieurs photos de votre galerie'
  ],
  'Imágenes': ['Images', 'Imagens', 'Images'],
  'Procesando {n} páginas…': ['Processing {n} pages…', 'Processando {n} páginas…', 'Traitement de {n} pages…'],
  'Escaneo {date}': ['Scan {date}', 'Escaneamento {date}', 'Numérisation {date}'],
  'Guardar aquí': ['Save here', 'Salvar aqui', 'Enregistrer ici'],

  // Camera
  'Necesitamos la cámara para escanear. Actívala en los ajustes del teléfono.': [
    'We need the camera to scan. Turn it on in your phone settings.',
    'Precisamos da câmera para escanear. Ative-a nos ajustes do celular.',
    'Nous avons besoin de la caméra pour numériser. Activez-la dans les réglages du téléphone.'
  ],
  'No se pudo abrir la cámara.': ['The camera couldn’t be opened.', 'Não foi possível abrir a câmera.', 'Impossible d’ouvrir la caméra.'],
  'La foto salió movida. Mantén el móvil quieto y vuelve a intentarlo.': [
    'The photo came out blurry. Hold the phone still and try again.',
    'A foto saiu tremida. Mantenha o celular parado e tente de novo.',
    'La photo est floue. Gardez le téléphone immobile et réessayez.'
  ],
  'No se pudo hacer la foto. Inténtalo de nuevo.': ['The photo couldn’t be taken. Try again.', 'Não foi possível tirar a foto. Tente de novo.', 'Impossible de prendre la photo. Réessayez.'],
  'Página {n} eliminada': ['Page {n} deleted', 'Página {n} excluída', 'Page {n} supprimée'],
  '¿Descartar {n} {pages}?': ['Discard {n} {pages}?', 'Descartar {n} {pages}?', 'Abandonner {n} {pages} ?'],
  'Las fotos que has hecho se perderán.': ['The photos you took will be lost.', 'As fotos que você tirou serão perdidas.', 'Les photos prises seront perdues.'],
  'Seguir escaneando': ['Keep scanning', 'Continuar escaneando', 'Continuer à numériser'],
  'Descartar': ['Discard', 'Descartar', 'Abandonner'],
  '1 foto salió movida: revísala al ajustar bordes.': [
    '1 photo came out blurry: check it when adjusting edges.',
    '1 foto saiu tremida: revise-a ao ajustar as bordas.',
    '1 photo est floue : vérifiez-la lors de l’ajustement des bords.'
  ],
  '{n} fotos salieron movidas: revísalas al ajustar bordes.': [
    '{n} photos came out blurry: check them when adjusting edges.',
    '{n} fotos saíram tremidas: revise-as ao ajustar as bordas.',
    '{n} photos sont floues : vérifiez-les lors de l’ajustement des bords.'
  ],
  'Iniciando la cámara…': ['Starting the camera…', 'Iniciando a câmera…', 'Démarrage de la caméra…'],
  'Muy oscuro · acércate a la luz': ['Too dark · move closer to the light', 'Muito escuro · aproxime-se da luz', 'Trop sombre · approchez-vous de la lumière'],
  'Poca luz · activa el flash': ['Low light · turn on the flash', 'Pouca luz · ative o flash', 'Peu de lumière · activez le flash'],
  'Buscando el documento…': ['Looking for the document…', 'Procurando o documento…', 'Recherche du document…'],
  'Hoja detectada': ['Sheet detected', 'Folha detectada', 'Feuille détectée'],
  'Hoja detectada · capturando…': ['Sheet detected · capturing…', 'Folha detectada · capturando…', 'Feuille détectée · capture…'],
  'Página {n} · hoja detectada': ['Page {n} · sheet detected', 'Página {n} · folha detectada', 'Page {n} · feuille détectée'],
  'La cámara no responde.': ['The camera isn’t responding.', 'A câmera não responde.', 'La caméra ne répond pas.'],
  'Cerrar cámara': ['Close camera', 'Fechar câmera', 'Fermer la caméra'],
  'Apagar el flash': ['Turn flash off', 'Desligar o flash', 'Éteindre le flash'],
  'Encender el flash': ['Turn flash on', 'Ligar o flash', 'Allumer le flash'],
  'Hacer foto': ['Take photo', 'Tirar foto', 'Prendre une photo'],
  'Deshacer la última página': ['Undo last page', 'Desfazer a última página', 'Annuler la dernière page'],
  '{n} {pages}. Continuar': ['{n} {pages}. Continue', '{n} {pages}. Continuar', '{n} {pages}. Continuer'],
  'Modificar': ['Edit', 'Editar', 'Modifier'],
  'Captura manual': ['Manual capture', 'Captura manual', 'Capture manuelle'],
  'Auto': ['Auto', 'Auto', 'Auto'],
  'Manual': ['Manual', 'Manual', 'Manuel'],
  'Necesitamos la cámara': ['We need the camera', 'Precisamos da câmera', 'Nous avons besoin de la caméra'],
  'No se puede usar la cámara': ['The camera can’t be used', 'Não é possível usar a câmera', 'Impossible d’utiliser la caméra'],
  'Abrir ajustes': ['Open settings', 'Abrir ajustes', 'Ouvrir les réglages'],
  'Reintentar': ['Retry', 'Tentar de novo', 'Réessayer'],
  'Ya la activé · Reintentar': ['I turned it on · Retry', 'Já ativei · Tentar de novo', 'Je l’ai activée · Réessayer'],
  'Individual': ['Single', 'Individual', 'Unique'],
  'Lote': ['Batch', 'Lote', 'Lot'],
  'Hecho': ['Done', 'Pronto', 'Terminé'],

  // Edit (crop / filter)
  '¿Eliminar esta página?': ['Delete this page?', 'Excluir esta página?', 'Supprimer cette page ?'],
  'La foto {n} se descartará y no se guardará.': [
    'Photo {n} will be discarded and not saved.',
    'A foto {n} será descartada e não será salva.',
    'La photo {n} sera abandonnée et non enregistrée.'
  ],
  'Ajustar bordes': ['Adjust edges', 'Ajustar bordas', 'Ajuster les bords'],
  'Página {n} de {total}': ['Page {n} of {total}', 'Página {n} de {total}', 'Page {n} sur {total}'],
  'Eliminar página {n}': ['Delete page {n}', 'Excluir página {n}', 'Supprimer la page {n}'],
  'Todo': ['All', 'Tudo', 'Tout'],
  'Izquierda': ['Left', 'Esquerda', 'Gauche'],
  'Derecha': ['Right', 'Direita', 'Droite'],
  'Siguiente': ['Next', 'Avançar', 'Suivant'],
  'Foto movida': ['Blurry photo', 'Foto tremida', 'Photo floue'],
  'Aplicar a todas las páginas': ['Apply to all pages', 'Aplicar a todas as páginas', 'Appliquer à toutes les pages'],
  'Guardar {n} páginas': ['Save {n} pages', 'Salvar {n} páginas', 'Enregistrer {n} pages'],
};
