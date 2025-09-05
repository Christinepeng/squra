import 'package:gal/gal.dart';

class GalleryService {
  static Future<bool> saveToGallery(String filePath) async {
    try {
      await Gal.putImage(filePath);
      return true;
    } catch (_) {
      return false;
    }
  }
}
