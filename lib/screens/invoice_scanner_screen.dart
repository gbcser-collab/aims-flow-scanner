[Reading 115 lines from start (total: 115 lines, 0 remaining)]

import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/aims_locale.dart';
import '../services/aims_scan_engine.dart';
import '../services/invoice_parser.dart';
import '../services/invoice_service.dart';
import '../services/ocr_service.dart';
import '../services/vehicle_tracking_service.dart';

class InvoiceScannerScreen extends StatefulWidget {
  const InvoiceScannerScreen({super.key,required this.camera});
  final CameraDescription camera;
  @override State<InvoiceScannerScreen> createState()=>_InvoiceScannerScreenState();
}

class _InvoiceScannerScreenState extends State<InvoiceScannerScreen> with WidgetsBindingObserver {
  CameraController? _camera; String? _imagePath; String _ocr=''; String _phase=''; String? _error;
  bool _busy=false,_sending=false,_createVignette=false; InvoiceCategory _category=InvoiceCategory.other;
  String _vignetteType='electronic'; DateTime? _validFrom,_validUntil;
  final _plate=TextEditingController(),_vendor=TextEditingController(),_date=TextEditingController(),_total=TextEditingController(),_currency=TextEditingController(),_doc=TextEditingController(),_note=TextEditingController(),_country=TextEditingController(),_liters=TextEditingController(),_unit=TextEditingController();

  static final List<String> _countries='AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW'.split(' ');

  String _l(String hu,String en,String de)=>switch(AimsLocaleController.instance.languageCode){'en'=>en,'de'=>de,_=>hu};

  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);VehicleTrackingService.instance.currentStatus().then((s){if(mounted)setState(()=>_plate.text=s.vehicleLabel);});_initCamera();}
  Future<void> _initCamera() async {
    if(_busy||_imagePath!=null)return;setState((){_busy=true;_error=null;});
    try{await _camera?.dispose();}catch(_){}
    final c=CameraController(widget.camera,ResolutionPreset.high,enableAudio:false,imageFormatGroup:ImageFormatGroup.jpeg);
    try{await c.initialize();try{await c.setFocusMode(FocusMode.auto);}catch(_){}try{await c.setFlashMode(FlashMode.auto);}catch(_){}if(!mounted){await c.dispose();return;}setState(()=>_camera=c);}
    catch(e){await c.dispose();if(mounted)setState(()=>_error=_l('A kamera nem indult el: ','Camera failed: ','Kamera konnte nicht gestartet werden: ')+e.toString());}
    finally{if(mounted)setState(()=>_busy=false);}
  }

  Future<void> _capture() async {
    final c=_camera;if(c==null||!c.value.isInitialized||_busy)return;
    setState((){_busy=true;_phase=_l('Számla fotózása…','Taking invoice photo…','Rechnung wird fotografiert…');_error=null;});
    final ocr=OcrService();XFile? shot;
    try{
      shot=await c.takePicture();final temp=await getTemporaryDirectory();final out=temp.path+'/aims_invoice_'+DateTime.now().microsecondsSinceEpoch.toString()+'.jpg';
      if(mounted)setState(()=>_phase=_l('Automatikus tisztítás, perspektíva és kontraszt…','Auto cleanup, perspective and contrast…','Automatische Bereinigung, Perspektive und Kontrast…'));
      String finalPath;
      try{final result=await const AimsScanEngine().process(inputPath:shot.path,outputPath:out);finalPath=result.outputPath;}catch(_){await File(shot.path).copy(out);finalPath=out;}
      if(mounted)setState(()=>_phase=_l('OCR + számlaadatok felismerése…','OCR + invoice recognition…','OCR + Rechnungserkennung…'));
      final text=await ocr.recognize(finalPath);final d=const InvoiceParser().parse(text);
      _ocr=text;_category=d.category;_vendor.text=d.vendor??'';_date.text=d.date??DateTime.now().toIso8601String().substring(0,10);_total.text=d.totalAmount?.toString()??'';_currency.text=d.currency??'';_doc.text=d.documentNumber??'';_country.text=d.countryCode??'';_liters.text=d.liters?.toString()??'';_unit.text=d.pricePerLiter?.toString()??'';
      if(_category==InvoiceCategory.tollVignette){_createVignette=true;_validFrom=DateTime.now();_validUntil=DateTime.now().add(const Duration(days:1));}
      await c.dispose();if(!mounted)return;setState((){_camera=null;_imagePath=finalPath;_phase='';});
    }catch(e){if(mounted)setState(()=>_error=_l('A számla feldolgozása nem sikerült: ','Invoice processing failed: ','Rechnungsverarbeitung fehlgeschlagen: ')+e.toString());}
    finally{await ocr.dispose();if(shot!=null){try{if(await File(shot.path).exists())await File(shot.path).delete();}catch(_){}}if(mounted)setState(()=>_busy=false);}
  }

  InvoiceData _current(){
    double? n(TextEditingController c)=>double.tryParse(c.text.trim().replaceAll(',','.'));String? v(TextEditingController c)=>c.text.trim().isEmpty?null:c.text.trim();
    return InvoiceData(category:_category,vendor:v(_vendor),date:v(_date),totalAmount:n(_total),currency:v(_currency)?.toUpperCase(),documentNumber:v(_doc),countryCode:v(_country)?.toUpperCase(),liters:n(_liters),pricePerLiter:n(_unit),rawText:_ocr,confidence:1);
  }

  Future<void> _send() async {
    final p=_imagePath;if(p==null||_sending)return;if(_plate.text.trim().length<4){setState(()=>_error='A jármű rendszáma hiányzik.');return;}
    if(_createVignette){if(!_countries.contains(_country.text.trim().toUpperCase())||_validFrom==null||_validUntil==null||!_validUntil!.isAfter(_validFrom!)){setState(()=>_error='A matrica országát és érvényességét ellenőrizd.');return;}}
    setState((){_sending=true;_error=null;});
    try{
      await VehicleTrackingService.instance.setVehicleLabel(_plate.text);final status=await VehicleTrackingService.instance.currentStatus();
      final result=await const InvoiceService().send(imagePath:p,deviceId:status.deviceId,plate:_plate.text,data:_current(),note:_note.text,createVignette:_createVignette,vignetteCountry:_country.text,vignetteType:_vignetteType,validFrom:_validFrom,validUntil:_validUntil);
      if(!mounted)return;ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(_l('Számla feltöltve a partnerportálra. ','Invoice uploaded to the partner portal. ','Rechnung ins Partnerportal hochgeladen. ')+result.invoiceId)));
      try{await File(p).delete();}catch(_){}Navigator.of(context).pop(true);
    }catch(e){if(mounted)setState(()=>_error=e.toString());}finally{if(mounted)setState(()=>_sending=false);}
  }

  Future<void> _retake() async {final p=_imagePath;if(p!=null){try{await File(p).delete();}catch(_){}}setState((){_imagePath=null;_ocr='';_error=null;});await _initCamera();}
  Future<DateTime?> _pickDateTime(DateTime? initial) async {final now=DateTime.now();final d=await showDatePicker(context:context,firstDate:DateTime(now.year-1),lastDate:DateTime(now.year+3),initialDate:initial??now);if(d==null||!mounted)return null;final t=await showTimePicker(context:context,initialTime:TimeOfDay.fromDateTime(initial??now));if(t==null)return DateTime(d.year,d.month,d.day);return DateTime(d.year,d.month,d.day,t.hour,t.minute);}
  String _dt(DateTime? d)=>d==null?'Nincs megadva':d.toLocal().toString().substring(0,16);

  @override void didChangeAppLifecycleState(AppLifecycleState s){if(s==AppLifecycleState.resumed&&_imagePath==null&&_camera==null)_initCamera();if(s==AppLifecycleState.paused||s==AppLifecycleState.inactive){final c=_camera;_camera=null;c?.dispose();}}
  @override void dispose(){WidgetsBinding.instance.removeObserver(this);_camera?.dispose();for(final c in [_plate,_vendor,_date,_total,_currency,_doc,_note,_country,_liters,_unit]){c.dispose();}super.dispose();}

  @override Widget build(BuildContext context)=>Scaffold(backgroundColor:const Color(0xFF0C0F13),appBar:AppBar(backgroundColor:const Color(0xFF0C0F13),foregroundColor:Colors.white,title:Text(_l('AIMS Számla Scanner','AIMS Invoice Scanner','AIMS Rechnungsscanner')),actions:const [Padding(padding:EdgeInsets.only(right:8),child:AimsLanguageSelector(compact:true))]),body:SafeArea(child:_imagePath==null?_cameraView():_review()));

  Widget _cameraView(){final c=_camera;return Stack(fit:StackFit.expand,children:[
    if(_error!=null&&c==null)Center(child:Padding(padding:const EdgeInsets.all(24),child:Text(_error!,style:const TextStyle(color:Colors.orangeAccent))))
    else if(c==null||!c.value.isInitialized)const Center(child:CircularProgressIndicator(color:Color(0xFFE6B85C))) else CameraPreview(c),
    Positioned(left:18,right:18,top:18,child:Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:Colors.black.withValues(alpha:.72),border:Border.all(color:const Color(0xFFE6B85C)),borderRadius:BorderRadius.circular(14)),child:Text(_l('Tartsd a teljes számlát a képen. AIMS automatikusan tisztítja, OCR-ezi és besorolja.','Keep the entire invoice in frame. AIMS cleans, reads and classifies it automatically.','Die gesamte Rechnung im Bild halten. AIMS bereinigt, liest und klassifiziert automatisch.'),textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w800)))),
    Positioned(left:28,right:28,top:120,bottom:130,child:IgnorePointer(child:Container(decoration:BoxDecoration(border:Border.all(color:Colors.white70,width:2),borderRadius:BorderRadius.circular(10))))),
    Positioned(left:0,right:0,bottom:26,child:Center(child:GestureDetector(onTap:_busy?null:_capture,child:Container(width:84,height:84,decoration:BoxDecoration(shape:BoxShape.circle,border:Border.all(color:Colors.white,width:5),color:Colors.white24),alignment:Alignment.center,child:Container(width:60,height:60,decoration:const BoxDecoration(shape:BoxShape.circle,color:Colors.white)))))),
    if(_busy)Positioned.fill(child:ColoredBox(color:Colors.black87,child:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[const CircularProgressIndicator(color:Color(0xFFE6B85C)),const SizedBox(height:16),Text(_phase,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w800))]))))
  ]);}

  Widget _review()=>ListView(padding:const EdgeInsets.all(16),children:[
    ClipRRect(borderRadius:BorderRadius.circular(12),child:Image.file(File(_imagePath!),height:230,fit:BoxFit.contain)),const SizedBox(height:14),
    Text(_l('Felismert számla','Recognized invoice','Erkannte Rechnung'),style:const TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.w900)),const SizedBox(height:12),
    DropdownButtonFormField<InvoiceCategory>(value:_category,dropdownColor:const Color(0xFF171A1F),style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w700),decoration:_deco('Kategória'),items:InvoiceCategory.values.map((c)=>DropdownMenuItem(value:c,child:Text(c.hu))).toList(),onChanged:(v)=>setState((){_category=v??InvoiceCategory.other;if(_category==InvoiceCategory.tollVignette){_createVignette=true;_validFrom??=DateTime.now();_validUntil??=DateTime.now().add(const Duration(days:1));}})),
    const SizedBox(height:10),_field('Rendszám',_plate,caps:true),_field('Kibocsátó / kereskedő',_vendor),_field('Számla dátuma (ÉÉÉÉ-HH-NN)',_date),
    Row(children:[Expanded(child:_field('Összeg',_total,number:true)),const SizedBox(width:8),Expanded(child:_field('Pénznem',_currency,caps:true))]),_field('Számla / bizonylat száma',_doc),
    if(_category==InvoiceCategory.fuel)Row(children:[Expanded(child:_field('Liter',_liters,number:true)),const SizedBox(width:8),Expanded(child:_field('Egységár / liter',_unit,number:true))]),
    _field('Megjegyzés',_note),
    if(_category==InvoiceCategory.tollVignette)...[
      SwitchListTile(value:_createVignette,onChanged:(v)=>setState(()=>_createVignette=v),activeColor:const Color(0xFFE6B85C),title:const Text('Matrica / útdíj automatikus rögzítése',style:TextStyle(color:Colors.white,fontWeight:FontWeight.w800))),
      if(_createVignette)...[
        DropdownButtonFormField<String>(value:_countries.contains(_country.text.toUpperCase())?_country.text.toUpperCase():null,dropdownColor:const Color(0xFF171A1F),menuMaxHeight:360,decoration:_deco('Ország'),items:_countries.map((c)=>DropdownMenuItem(value:c,child:Text(c))).toList(),onChanged:(v)=>setState(()=>_country.text=v??'')),
        const SizedBox(height:10),DropdownButtonFormField<String>(value:_vignetteType,dropdownColor:const Color(0xFF171A1F),decoration:_deco('Típus'),items:const [DropdownMenuItem(value:'electronic',child:Text('Elektronikus matrica / e-útdíj')),DropdownMenuItem(value:'point_of_sale',child:Text('Helyszínen vásárolt / bizonylatos'))],onChanged:(v)=>setState(()=>_vignetteType=v??'electronic')),
        const SizedBox(height:10),Row(children:[Expanded(child:OutlinedButton(onPressed:()async{final x=await _pickDateTime(_validFrom);if(x!=null)setState(()=>_validFrom=x);},child:Text('Kezdés\n'+_dt(_validFrom),textAlign:TextAlign.center))),const SizedBox(width:8),Expanded(child:OutlinedButton(onPressed:()async{final x=await _pickDateTime(_validUntil);if(x!=null)setState(()=>_validUntil=x);},child:Text('Vége\n'+_dt(_validUntil),textAlign:TextAlign.center)))])
      ]
    ],
    if(_error!=null)...[const SizedBox(height:8),Text(_error!,style:const TextStyle(color:Colors.orangeAccent,fontWeight:FontWeight.w700))],const SizedBox(height:14),
    FilledButton.icon(onPressed:_sending?null:_send,icon:_sending?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.cloud_upload_rounded),label:Text(_sending?'Feltöltés…':'FELTÖLTÉS A PARTNERPORTÁLRA'),style:FilledButton.styleFrom(minimumSize:const Size.fromHeight(62),backgroundColor:const Color(0xFFE6B85C),foregroundColor:Colors.black)),
    const SizedBox(height:8),OutlinedButton.icon(onPressed:_sending?null:_retake,icon:const Icon(Icons.refresh_rounded),label:const Text('ÚJRAFOTÓZÁS'),style:OutlinedButton.styleFrom(minimumSize:const Size.fromHeight(54),foregroundColor:Colors.white)),
    ExpansionTile(collapsedIconColor:Colors.white54,iconColor:const Color(0xFFE6B85C),title:const Text('OCR nyers szöveg',style:TextStyle(color:Colors.white70)),children:[Padding(padding:const EdgeInsets.all(12),child:SelectableText(_ocr,style:const TextStyle(color:Colors.white60)))])
  ]);

  InputDecoration _deco(String label)=>InputDecoration(labelText:label,labelStyle:const TextStyle(color:Colors.white54),filled:true,fillColor:const Color(0xFF171A1F),border:OutlineInputBorder(borderRadius:BorderRadius.circular(12),borderSide:BorderSide.none));
  Widget _field(String label,TextEditingController c,{bool number=false,bool caps=false})=>Padding(padding:const EdgeInsets.only(bottom:10),child:TextField(controller:c,keyboardType:number?const TextInputType.numberWithOptions(decimal:true):null,textCapitalization:caps?TextCapitalization.characters:TextCapitalization.sentences,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w700),decoration:_deco(label)));
}

[executed on device: GABOR-PC (4f5060cc-3a10-4200-947d-55b7a0fc1e22)]