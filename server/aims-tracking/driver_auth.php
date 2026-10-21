<?php
declare(strict_types=1);
require_once __DIR__.'/bootstrap.php';
require_once __DIR__.'/flow_auth.php';
header('Cache-Control: no-store');
header('Pragma: no-cache');
try {
    if (($_SERVER['REQUEST_METHOD']??'') !== 'POST') throw new FlowAuthError('method_not_allowed',405);
    $raw=file_get_contents('php://input')?:'';
    if (strlen($raw)>4096) throw new FlowAuthError('invalid_payload',422);
    $data=json_decode($raw,true);
    if (!is_array($data)) throw new FlowAuthError('invalid_json',400);
    $auth=flow_auth_service();
    $action=$data['action']??'';
    if ($action==='login') aims_json($auth->login($data,(string)($_SERVER['REMOTE_ADDR']??'unknown')));
    $device=(string)($_SERVER['HTTP_X_FLOW_DEVICE']??'');
    if ($action==='session') {
        $i=$auth->access(aims_bearer(),$device);
        aims_json(['ok'=>true,'subjectId'=>$i['subjectId'],'tenantId'=>$i['tenantId'],
            'assignmentId'=>$i['assignmentId'],'plate'=>$i['plate']]);
    }
    if (!is_string($data['refreshToken']??null)) throw new FlowAuthError('invalid_payload',422);
    if ($action==='refresh') aims_json($auth->refresh($data['refreshToken'],$device));
    if ($action==='logout') { $auth->logout($data['refreshToken'],$device); aims_json(['ok'=>true]); }
    throw new FlowAuthError('invalid_payload',422);
} catch (Throwable $e) { flow_auth_reply_error($e); }
