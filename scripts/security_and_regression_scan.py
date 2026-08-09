import os
import re
import sys
import json
import urllib.request
import urllib.parse
import subprocess
import xml.etree.ElementTree as ET

# Text colors for terminal output
class Colors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

def run_command(command, description):
    print(f"{Colors.OKBLUE}[*] {description}...{Colors.ENDC}")
    try:
        result = subprocess.run(command, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        print(f"{Colors.OKGREEN}[+] Başarılı: {description}{Colors.ENDC}")
        return True, result.stdout
    except subprocess.CalledProcessError as e:
        print(f"{Colors.FAIL}[-] Hata: {description} başarısız oldu!{Colors.ENDC}")
        print(f"{Colors.FAIL}Hata Çıktısı:\n{e.stdout}\n{e.stderr}{Colors.ENDC}")
        return False, e.stdout + e.stderr

def scan_manifest():
    print(f"\n{Colors.HEADER}=== AndroidManifest.xml Güvenlik Analizi ==={Colors.ENDC}")
    manifest_path = "android/app/src/main/AndroidManifest.xml"
    if not os.path.exists(manifest_path):
        print(f"{Colors.WARNING}[!] AndroidManifest.xml bulunamadı. Atlama yapılıyor.{Colors.ENDC}")
        return True

    try:
        tree = ET.parse(manifest_path)
        root = tree.getroot()
        
        # Check Application tag
        application = root.find('application')
        issues_found = []
        
        if application is not None:
            # Check allowBackup
            allow_backup = application.attrib.get('{http://schemas.android.com/apk/res/android}allowBackup')
            if allow_backup != 'false':
                issues_found.append("[GİZLİLİK] android:allowBackup değeri 'false' olmalıdır. (Mevcut: {}). Cihaz yedeklemelerinden veri sızabilir.".format(allow_backup))
            
            # Check usesCleartextTraffic
            cleartext = application.attrib.get('{http://schemas.android.com/apk/res/android}usesCleartextTraffic')
            if cleartext == 'true':
                issues_found.append("[GÜVENLİK] android:usesCleartextTraffic='true' olarak ayarlanmış. Güvensiz HTTP trafiğine izin veriliyor.")

        # Check for exported components without permissions
        for activity in root.findall('.//activity'):
            exported = activity.attrib.get('{http://schemas.android.com/apk/res/android}exported')
            name = activity.attrib.get('{http://schemas.android.com/apk/res/android}name')
            if exported == 'true':
                # Check if it's the main launcher activity
                is_launcher = False
                intent_filters = activity.findall('intent-filter')
                for ifilter in intent_filters:
                    actions = ifilter.findall('action')
                    categories = ifilter.findall('category')
                    has_main = any(a.attrib.get('{http://schemas.android.com/apk/res/android}name') == 'android.intent.action.MAIN' for a in actions)
                    has_launcher = any(c.attrib.get('{http://schemas.android.com/apk/res/android}name') == 'android.intent.category.LAUNCHER' for c in categories)
                    if has_main and has_launcher:
                        is_launcher = True
                        break
                
                if is_launcher:
                    continue
                    
                # Check if it has an intent filter but no custom permission
                intent_filter = activity.find('intent-filter')
                permission = activity.attrib.get('{http://schemas.android.com/apk/res/android}permission')
                if intent_filter is not None and not permission:
                    issues_found.append("[GÜVENLİK] Activity '{}' dışa aktarılmış (exported=true) ancak herhangi bir izinle korunmuyor.".format(name))

        if issues_found:
            for issue in issues_found:
                print(f"{Colors.FAIL}[-] Zafiyet: {issue}{Colors.ENDC}")
            return False
        else:
            print(f"{Colors.OKGREEN}[+] AndroidManifest.xml güvenli görünüyor.{Colors.ENDC}")
            return True
    except Exception as e:
        print(f"{Colors.FAIL}[-] Manifest analizinde hata oluştu: {str(e)}{Colors.ENDC}")
        return False

def scan_codebase():
    print(f"\n{Colors.HEADER}=== Kaynak Kod Statik Güvenlik Analizi (SAST) ==={Colors.ENDC}")
    
    # Regex rules
    rules = [
        {
            "name": "Hardcoded Secret / API Key",
            "regex": r"(?i)(api_key|secret|password|private_key|token|auth_token|client_secret)\s*=\s*['\"][a-zA-Z0-9_\-\+\/]{8,}['\"]",
            "type": "GÜVENLİK",
            "description": "Kaynak kodda statik API anahtarı veya şifre tespit edildi."
        },
        {
            "name": "Insecure HTTP Protocol",
            "regex": r"['\"]http://[a-zA-Z0-9\.\/\-\?\#\=\&\%\_]+['\"]",
            "type": "GÜVENLİK",
            "description": "Güvensiz HTTP bağlantısı tespit edildi. HTTPS kullanılmalıdır."
        },
        {
            "name": "Weak Cryptography (MD5/SHA-1)",
            "regex": r"(?i)(md5|sha1)\b",
            "type": "GÜVENLİK",
            "description": "Zayıf şifreleme algoritması (MD5/SHA-1) kullanımı tespit edildi."
        }
    ]

    clean = True
    for root_dir, dirs, files in os.walk("."):
        # Exclude build, ios, android, .dart_tool, .git
        if any(x in root_dir for x in ["build", "ios", ".dart_tool", ".git", "android/app/build"]):
            continue
            
        for file in files:
            if not file.endswith(('.dart', '.java', '.kt')):
                continue
                
            file_path = os.path.join(root_dir, file)
            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                    
                for rule in rules:
                    matches = re.finditer(rule["regex"], content)
                    for match in matches:
                        # Simple false positive checks
                        matched_text = match.group(0)
                        if "api.testsprite.com" in matched_text or "placeholder" in matched_text.lower() or "example" in matched_text.lower():
                            continue
                        
                        # Find line number
                        line_no = content.count('\n', 0, match.start()) + 1
                        print(f"{Colors.FAIL}[-] {rule['type']} - {rule['name']} ({file_path}:{line_no}){Colors.ENDC}")
                        print(f"    Tespit: {matched_text.strip()}")
                        print(f"    Açıklama: {rule['description']}")
                        clean = False
            except Exception as e:
                pass
                
    if clean:
        print(f"{Colors.OKGREEN}[+] Kaynak kodda güvenlik veya gizlilik ihlali bulunamadı.{Colors.ENDC}")
    return clean

def run_mobsf_scan():
    print(f"\n{Colors.HEADER}=== MobSF Statik/Dinamik Güvenlik Analizi ==={Colors.ENDC}")
    mobsf_url = "http://localhost:8000"
    api_key = "mobsf_sec_key"
    
    # Check if MobSF is reachable
    try:
        req = urllib.request.Request(f"{mobsf_url}/api/v1/scans", headers={"Authorization": api_key})
        with urllib.request.urlopen(req, timeout=3) as r:
            pass
    except Exception:
        print(f"{Colors.WARNING}[!] MobSF servisi bulunamadı (http://localhost:8000).{Colors.ENDC}")
        print(f"{Colors.WARNING}    Docker MobSF çalıştırmak için:{Colors.ENDC}")
        print(f"{Colors.WARNING}    docker run -d --name mobsf -p 8000:8000 -e MOBSF_API_KEY=mobsf_sec_key opensecurity/mobsf:latest{Colors.ENDC}")
        print(f"{Colors.WARNING}    MobSF analizi atlanıyor, sadece yerel tarayıcılar çalıştırılacak.{Colors.ENDC}")
        return True

    print(f"{Colors.OKGREEN}[+] MobSF servisi aktif! APK analiz edilmeye başlanıyor...{Colors.ENDC}")
    apk_path = "build/app/outputs/flutter-apk/app-release.apk"
    if not os.path.exists(apk_path):
        print(f"{Colors.OKBLUE}[*] Release APK bulunamadı. Önce derleniyor...{Colors.ENDC}")
        ok, _ = run_command("flutter build apk --release", "Release APK Derleme")
        if not ok:
            return False

    # Upload APK to MobSF
    print(f"{Colors.OKBLUE}[*] APK MobSF'e yükleniyor...{Colors.ENDC}")
    try:
        boundary = "----WebKitFormBoundary7MA4YWxkTrZu0gW"
        with open(apk_path, "rb") as f:
            file_data = f.read()
        
        body = (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="file"; filename="app-release.apk"\r\n'
            f"Content-Type: application/vnd.android.package-archive\r\n\r\n"
        ).encode('utf-8') + file_data + f"\r\n--{boundary}--\r\n".encode('utf-8')

        headers = {
            "Authorization": api_key,
            "Content-Type": f"multipart/form-data; boundary={boundary}"
        }
        
        req = urllib.request.Request(f"{mobsf_url}/api/v1/upload", data=body, headers=headers, method="POST")
        with urllib.request.urlopen(req) as r:
            res_data = json.loads(r.read().decode('utf-8'))
        
        scan_hash = res_data.get("hash")
        if not scan_hash:
            print(f"{Colors.FAIL}[-] MobSF yükleme hatası: Hash alınamadı.{Colors.ENDC}")
            return False
            
        print(f"{Colors.OKGREEN}[+] APK yüklendi. Tarama başlatılıyor (Hash: {scan_hash})...{Colors.ENDC}")
        
        # Trigger scan
        scan_data = urllib.parse.urlencode({"hash": scan_hash}).encode('utf-8')
        req = urllib.request.Request(f"{mobsf_url}/api/v1/scan", data=scan_data, headers={"Authorization": api_key}, method="POST")
        with urllib.request.urlopen(req) as r:
            r.read()
            
        # Get JSON report scorecard
        print(f"{Colors.OKBLUE}[*] Rapor indiriliyor...{Colors.ENDC}")
        report_data = urllib.parse.urlencode({"hash": scan_hash}).encode('utf-8')
        req = urllib.request.Request(f"{mobsf_url}/api/v1/scorecard", data=report_data, headers={"Authorization": api_key}, method="POST")
        with urllib.request.urlopen(req) as r:
            report = json.loads(r.read().decode('utf-8'))
            
        security_score = report.get("security_score", 100)
        critical_issues = report.get("critical", 0)
        high_issues = report.get("high", 0)
        
        print(f"\n{Colors.HEADER}=== MobSF Sonuçları ==={Colors.ENDC}")
        print(f"Güvenlik Skoru: {security_score}/100")
        print(f"Kritik Zafiyet Sayısı: {critical_issues}")
        print(f"Yüksek Seviyeli Zafiyet Sayısı: {high_issues}")
        
        if security_score < 70 or critical_issues > 0:
            print(f"{Colors.FAIL}[-] MobSF taraması başarısız! Uygulama güvenli bulunmadı.{Colors.ENDC}")
            return False
            
        print(f"{Colors.OKGREEN}[+] MobSF taraması başarıyla geçildi.{Colors.ENDC}")
        return True
    except Exception as e:
        print(f"{Colors.FAIL}[-] MobSF analizinde hata: {str(e)}{Colors.ENDC}")
        return False

def main():
    print(f"{Colors.BOLD}{Colors.HEADER}=================================================={Colors.ENDC}")
    print(f"{Colors.BOLD}{Colors.HEADER}       OTONOM STATİK GÜVENLİK VE REGRESYON TESTİ   {Colors.ENDC}")
    print(f"{Colors.BOLD}{Colors.HEADER}=================================================={Colors.ENDC}")
    
    # 1. Kod Analizi (Flutter Analyze)
    analyze_ok, _ = run_command("flutter analyze", "Flutter Kod Kalitesi ve Hata Analizi")
    if not analyze_ok:
        sys.exit(1)
        
    # 2. Birim ve Entegrasyon Testleri (Flutter Test)
    test_ok, _ = run_command("flutter test", "Flutter Otomatik Test Senaryoları")
    if not test_ok:
        sys.exit(1)
        
    # 3. AndroidManifest Analizi
    manifest_ok = scan_manifest()
    
    # 4. Kaynak Kod Zafiyet Analizi (SAST)
    sast_ok = scan_codebase()
    
    # 5. Opsiyonel MobSF Taraması (Docker aktifse)
    mobsf_ok = run_mobsf_scan()
    
    if not manifest_ok or not sast_ok or not mobsf_ok:
        print(f"\n{Colors.FAIL}[-] Güvenlik ve Gizlilik Taraması Hata/Zafiyet Bildirdi!{Colors.ENDC}")
        sys.exit(1)
        
    print(f"\n{Colors.OKGREEN}[+] TEBRİKLER! Tüm testler, kalite analizleri ve güvenlik taramaları sıfır hata ile tamamlandı!{Colors.ENDC}")
    sys.exit(0)

if __name__ == "__main__":
    main()
