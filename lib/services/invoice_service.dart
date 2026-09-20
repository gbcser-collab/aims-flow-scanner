import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'invoice_parser.dart';

class InvoiceUploadResult {
  const InvoiceUploadResult({required this.invoiceId,this.vignetteId});
  final String invoiceId; final String? vignetteId;
}

class InvoiceService {
  const InvoiceService();
  static const _endpoint=String.fromEnvironment('AIMS_INVOICE_ENDPOINT',defaultValue:'https://logistic-aims.hu/api/aims-tracking/vehicle_invoice.php');
  static const _token=String.fromEnvironment('AIMS_TRACKING_TOKEN',defaultValue:'');
  Future<InvoiceUploadResult> send({required String imagePath,required String deviceId,required String plate,required InvoiceData data,String note='',bool createVignette=false,String vignetteCountry='',String vignetteType='electronic',DateTime? validFrom,DateTime? validUntil}) async {
    if(_token.trim().isEmpty)throw StateError('A céges feltöltési kulcs nincs beállítva.');
    final file=File(imagePath);if(!await file.exists())throw StateError('A számla képe nem található.');
    final bytes=await file.readAsBytes();
    final response=await http.post(Uri.parse(_endpoint),headers:{'Content-Type':'application/json','Authorization':'Bearer '+_token},body:jsonEncode({
      'deviceId':deviceId,'plate':plate.trim().toUpperCase(),'capturedAt':DateTime.now().toUtc().toIso8601String(),
      'category':data.category.wire,'vendor':data.vendor,'invoiceDate':data.date,'totalAmount':data.totalAmount,'currency':data.currency,'documentNumber':data.documentNumber,'note':note.trim(),'ocrText':data.rawText,'liters':data.liters,'pricePerLiter':data.pricePerLiter,'confidence':data.confidence,
      'createVignette':createVignette,'vignetteCountry':vignetteCountry.trim().toUpperCase(),'vignetteType':vignetteType,'validFrom':validFrom?.toUtc().toIso8601String(),'validUntil':validUntil?.toUtc().toIso8601String(),
      'image':{'mimeType':'image/jpeg','base64':base64Encode(bytes)}
    })).timeout(const Duration(seconds:45));
    Map<String,dynamic> body={};try{final d=jsonDecode(response.body);if(d is Map)body=Map<String,dynamic>.from(d);}catch(_){}
    if(response.statusCode<200||response.statusCode>=300||body['ok']!=true){throw StateError('Számlafeltöltési hiba: '+(body['error']?.toString()??('HTTP '+response.statusCode.toString())));}
    return InvoiceUploadResult(invoiceId:body['invoiceId']?.toString()??'',vignetteId:body['vignetteId']?.toString());
  }
}