import base64
import hashlib
import hmac
import json
import sys
import time

def base64url_encode(data):
    if isinstance(data, str):
        data = data.encode('utf-8')
    return base64.urlsafe_b64encode(data).replace(b'=', b'').decode('utf-8')

def generate_jwt(jwt_secret, role, issuer):
    header = {"alg": "HS256", "typ": "JWT"}
    header_b64 = base64url_encode(json.dumps(header, separators=(',', ':')))

    current_timestamp = int(time.time())
    # Approx 5 years, same as in the bash script (157,680,000 seconds)
    expiry_timestamp = current_timestamp + 157680000 

    payload = {
        "role": role,
        "iss": issuer,
        "iat": current_timestamp,
        "exp": expiry_timestamp
    }
    payload_b64 = base64url_encode(json.dumps(payload, separators=(',', ':')))

    signature_input = f"{header_b64}.{payload_b64}"
    
    signature = hmac.new(
        jwt_secret.encode('utf-8'),
        signature_input.encode('utf-8'),
        hashlib.sha256
    ).digest()
    signature_b64 = base64url_encode(signature)

    return f"{header_b64}.{payload_b64}.{signature_b64}"

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: python generate_jwt.py <jwt_secret> <role> <issuer>", file=sys.stderr)
        sys.exit(1)

    jwt_secret_arg = sys.argv[1]
    role_arg = sys.argv[2]
    issuer_arg = sys.argv[3]

    jwt_token = generate_jwt(jwt_secret_arg, role_arg, issuer_arg)
    print(jwt_token)
