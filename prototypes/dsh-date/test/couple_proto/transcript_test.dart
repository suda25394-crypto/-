import 'package:dsh_app/couple_proto/couple_transcript.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('renders only the supplied conversation with durable source ids and authors', () {
    final human = <String,dynamic>{'id':'r1','role':'user','owner':'alice','text':'推迟半小时','request_id':'r1'};
    final reply = <String,dynamic>{'id':'r1-ai','role':'assistant','owner':'alice','text':'请确认新时间','request_id':'r1'};
    final bob = <String,dynamic>{'id':'r2','role':'user','owner':'bob','text':'收到'};
    final lines = projectTranscript([human,reply,bob,human],'alice');
    expect(lines.map((x)=>x.id), ['r1','r1-ai','r2']);
    expect(lines.map((x)=>x.authorLabel), ['我','DP','伴侣']);
    expect(lines.map((x)=>x.text), ['推迟半小时','请确认新时间','收到']);
    expect(projectTranscript([], 'bob'), isEmpty);
  });
}
