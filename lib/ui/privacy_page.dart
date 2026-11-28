import 'package:flutter/material.dart';

class PicdoriPrivacyPage extends StatelessWidget {
  const PicdoriPrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    const sections = [
      (
        '사진 선택과 변환',
        '두도지공방의 픽도리는 사용자가 선택한 사진을 읽어 기기에서 크기, 용량, 파일 형식을 변환합니다. 픽도리 운영 서버로 원본이나 결과 사진을 보내지 않습니다. 원본 사진은 변경하지 않습니다.',
      ),
      (
        '기기에 보관하는 정보',
        '완성한 사진은 앱의 ‘내 파일’에 자동 보관합니다. 다시 찾거나 같은 조건으로 작업할 수 있도록 파일 이름, 크기, 형식, 작업 시각과 변환 조건 등을 앱 저장 공간에 기록합니다. 저장·공유 과정에서 기기 임시 폴더에 결과 사본을 만들 수 있습니다.',
      ),
      (
        '보관 기간과 삭제',
        '내 파일에서 삭제한 사진은 ‘최근 삭제’에서 7일 동안 복구할 수 있습니다. 직접 영구 삭제하거나, 기한이 지난 뒤 앱에서 보관함을 정리할 때 삭제됩니다. 최근 작업 기록은 별도로 삭제할 수 있습니다. 사진첩이나 파일 앱에 직접 저장한 사본은 그 위치에서 삭제할 수 있습니다. 기기 백업이나 사진 동기화는 사용 중인 기기와 서비스 설정을 따릅니다.',
      ),
      (
        '저장과 공유',
        '‘사진첩 저장’이나 ‘파일 저장’을 누르면 지정한 위치에 결과 사본을 저장합니다. ‘공유하기’에서 사용자가 앱이나 수신처를 선택하면 해당 대상에 결과 사진이 전달됩니다. 이후의 보관과 이용은 선택한 서비스의 정책을 따릅니다.',
      ),
      (
        '의견과 문의',
        '‘의견 보내기’는 메일 작성 화면을 엽니다. 사용자가 직접 메일을 보내면 두도지공방은 회신 주소, 메일 본문, 직접 첨부한 자료를 문의 대응에 사용합니다. 앱에서 사진이나 진단 로그를 자동 첨부하지 않습니다. 문의 대응과 후속 확인이 끝나면 문의 자료를 삭제하며, 법령상 보관이 필요한 자료는 해당 기간이 지난 뒤 삭제합니다.',
      ),
      (
        '문의 및 삭제 요청',
        '운영자는 두도지공방(Dudozi Workshop)입니다. 문의 메일에 포함한 정보의 열람·삭제 요청 또는 개인정보 관련 문의는 dudoziworkshop@gmail.com으로 보내 주세요. 요청 내용을 확인하고 처리 결과를 회신합니다.',
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('개인정보처리방침')),
      body: SafeArea(child: SelectionArea(child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final (heading, body) in sections) ...[
            Semantics(header: true, child: Text(heading,
                style: Theme.of(context).textTheme.titleMedium)),
            const SizedBox(height: 6),
            Text(body, style: const TextStyle(height: 1.55)),
            const SizedBox(height: 20),
          ],
        ],
      ))),
    );
  }
}
