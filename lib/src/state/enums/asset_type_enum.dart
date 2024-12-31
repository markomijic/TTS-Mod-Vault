enum AssetType {
  assetBundle('AssetBundles', [
    'AssetbundleSecondaryURL',
    'AssetbundleURL',
  ]),

  audio('Audio', [
    'CurrentAudioURL',
    'Item1',
  ]),

  image('Images', [
    'BackURL',
    'DiffuseURL',
    'FaceURL',
    'ImageSecondaryURL',
    'ImageURL',
    'LutURL',
    'NormalURL',
    'SkyURL',
    'TableURL',
    'URL',
  ]),

  model('Models', [
    'ColliderURL',
    'MeshURL',
  ]),

  pdf('PDF', [
    'PDFUrl',
  ]);

  final String label;
  final List<String> subtypes;

  const AssetType(this.label, this.subtypes);
}
