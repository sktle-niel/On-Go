import 'package:flutter_test/flutter_test.dart';
import 'package:on_go/data/job_photo_store.dart';
import 'package:on_go/services/local/record_box.dart';

/// `JobPhotoStore` — the photos a client attached, kept beside the job.
///
/// They live here rather than on the job record because the contract carries
/// none: a path is meaningful only on the phone that took the picture, and the
/// server has nowhere to put the bytes yet. What matters is that a screen can
/// ask any job for its photos and get an answer, and that closing the app does
/// not lose them.
void main() {
  late JobPhotoStore photos;
  late MemoryRecordBox box;

  setUp(() {
    box = MemoryRecordBox();
    photos = JobPhotoStore.instance..debugUse(box);
  });

  test('a job with no photos answers empty rather than null', () {
    expect(photos.pathsFor('job-1'), isEmpty);
    expect(photos.hasPhotos('job-1'), isFalse);
  });

  test('photos are filed against the id the backend gave the job', () {
    photos.attach('job-1', ['/tmp/a.jpg', '/tmp/b.jpg']);

    expect(photos.pathsFor('job-1'), ['/tmp/a.jpg', '/tmp/b.jpg']);
    expect(photos.hasPhotos('job-1'), isTrue);
    // One job's photos are not another's.
    expect(photos.pathsFor('job-2'), isEmpty);
  });

  test('the order they were picked in is the order they are shown in', () {
    photos.attach('job-1', ['/tmp/c.jpg', '/tmp/a.jpg', '/tmp/b.jpg']);

    expect(photos.pathsFor('job-1'), ['/tmp/c.jpg', '/tmp/a.jpg', '/tmp/b.jpg']);
  });

  test('attaching nothing leaves no entry behind', () {
    photos.attach('job-1', const []);
    photos.attach('job-2', ['', '   ']);

    expect(photos.hasPhotos('job-1'), isFalse);
    expect(photos.hasPhotos('job-2'), isFalse);
  });

  test('a cancelled booking\'s photos are forgotten', () {
    photos.attach('job-1', ['/tmp/a.jpg']);

    photos.forget('job-1');

    expect(photos.pathsFor('job-1'), isEmpty);
  });

  test('photos survive the app being closed', () async {
    photos.attach('job-1', ['/tmp/a.jpg', '/tmp/b.jpg']);
    await Future<void>.delayed(Duration.zero);

    // A fresh launch, reading the same box back.
    final reopened = JobPhotoStore.instance..debugUse(box);
    expect(reopened.pathsFor('job-1'), isEmpty, reason: 'nothing until load()');
    await reopened.load();

    expect(reopened.pathsFor('job-1'), ['/tmp/a.jpg', '/tmp/b.jpg']);
  });

  test('a listener hears an attachment, so a job card repaints', () {
    var heard = 0;
    void listener() => heard++;
    photos.addListener(listener);

    photos.attach('job-1', ['/tmp/a.jpg']);
    photos.forget('job-1');

    expect(heard, 2);
    photos.removeListener(listener);
  });
}
