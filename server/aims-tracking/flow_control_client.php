<?php
declare(strict_types=1);

/** CONTROL owns credentials and entitlements. No PIN or PIN hash is stored in FLOW. */
interface FlowControlProvider {
    public function verify(string $flowId, string $pin): array;
    public function authorize(array $identity): array;
}

final class FlowAuthError extends RuntimeException {
    public function __construct(public readonly string $error, public readonly int $status) {
        parent::__construct($error);
    }
}

final class FlowControlHttpClient implements FlowControlProvider {
    private function call(string $operation, array $payload): array {
        $base = rtrim((string)getenv('AIMS_CONTROL_FLOW_URL'), '/');
        $key = (string)getenv('AIMS_CONTROL_FLOW_SERVICE_TOKEN');
        $parts = parse_url($base);
        if (getenv('AIMS_FLOW_ID_AUTH_ENABLED') !== '1' || !$parts ||
            ($parts['scheme'] ?? '') !== 'https' || empty($parts['host']) ||
            isset($parts['user']) || isset($parts['pass']) || isset($parts['query']) ||
            isset($parts['fragment']) || strlen($key) < 32 || !function_exists('curl_init')) {
            throw new FlowAuthError('identity_unavailable', 503);
        }
        $ch = curl_init($base . '/' . $operation);
        $ca = (string)getenv('AIMS_CONTROL_CA_FILE');
        if ($ca !== '') curl_setopt($ch, CURLOPT_CAINFO, $ca);
        curl_setopt_array($ch, [
            CURLOPT_POST => true, CURLOPT_RETURNTRANSFER => true,
            CURLOPT_FOLLOWLOCATION => false, CURLOPT_PROTOCOLS => CURLPROTO_HTTPS,
            CURLOPT_CONNECTTIMEOUT => 3, CURLOPT_TIMEOUT => 8,
            CURLOPT_SSL_VERIFYPEER => true, CURLOPT_SSL_VERIFYHOST => 2,
            CURLOPT_HTTPHEADER => ['Content-Type: application/json', 'Accept: application/json',
                'Authorization: Bearer ' . $key],
            CURLOPT_POSTFIELDS => json_encode($payload, JSON_THROW_ON_ERROR),
        ]);
        $raw = curl_exec($ch);
        $status = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        curl_close($ch);
        // Never include upstream response bodies, credentials or tokens in errors/logs.
        if ($status === 401 || $status === 403) throw new FlowAuthError('invalid_credentials', 401);
        if ($status === 429) throw new FlowAuthError('rate_limited', 429);
        if ($status !== 200 || !is_string($raw) || strlen($raw) > 32768) {
            throw new FlowAuthError('identity_unavailable', 503);
        }
        $body = json_decode($raw, true);
        if (!is_array($body) || ($body['ok'] ?? null) !== true || !is_array($body['identity'] ?? null)) {
            throw new FlowAuthError('identity_unavailable', 503);
        }
        return $body['identity'];
    }
    public function verify(string $flowId, string $pin): array {
        return $this->call('verify', ['flowId' => $flowId, 'pin' => $pin]);
    }
    public function authorize(array $identity): array {
        return $this->call('authorize', [
            'subjectId' => $identity['subjectId'], 'tenantId' => $identity['tenantId'],
            'assignmentId' => $identity['assignmentId'],
            'credentialVersion' => $identity['credentialVersion'],
        ]);
    }
}
