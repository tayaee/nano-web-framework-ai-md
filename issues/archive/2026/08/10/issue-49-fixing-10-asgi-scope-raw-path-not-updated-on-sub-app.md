# issue-49: fixing-10 — ASGI scope `raw_path` 미갱신으로 서브앱 라우팅 불일치 (must-fix)

## 부모
issue-10 (ASGI 디스패처)

## 출처
- `issues/issue-10__TYPE-code-review__BY-gemini.md` Finding 1 (must-fix / correctness)
- `issues/issue-10__TYPE-code-review__BY-sonnet.md` §1 Verdict 1 (CONFIRMED)

## 문제
main.py의 서브앱 위임 코드가 sub_scope의 `path`/`root_path`만 갱신하고 `raw_path`는 원본 그대로 남긴다.

```python
# engine/aimd/main.py:78-82
app = self.registry.get(name, py)
sub_scope = dict(scope)
sub_scope["root_path"] = f"/{name}"
sub_scope["path"] = subpath or "/"
return await app(sub_scope, receive, send)
```

ASGI 스펙을 엄격히 따르는 서브앱(Quart, 일부 커스텀 게이트웨이)은 `scope["raw_path"]`(bytes)를 우선 사용한다. 따라서 `POST /api.ai.md/convert` 요청이 인입되면 subapp은 `raw_path=b"/api.ai.md/convert"`를 보고 내부 라우트 매칭에 실패해 404를 반환한다.

## 실패 시나리오
- 입력: ASGITransport가 scope에 `raw_path=b"/api.ai.md/convert"`를 채워 보낸 상태
- 잘못된 결과: 서브앱 내부에서 `/api.ai.md/convert` 경로로 라우트 매칭 시도 → 404

## 확인 방법 (Sonnet 재현 결과)
```
Status: 200
Body: {'path': '/convert', 'raw_path': '/api.ai.md/convert', 'root_path': '/api.ai.md'}
```

## 권장 구현 방향
sub_scope 갱신 시 raw_path도 path에 맞춰 재계산:
```python
sub_scope["path"] = subpath or "/"
if "raw_path" in sub_scope:
    sub_scope["raw_path"] = sub_scope["path"].encode("latin-1")
```
또는 spec이 정의하는 URL 계약이 subpath-only path를 보장하므로 path의 bytes 인코딩(latin-1 / UTF-8 percent-encoding)을 그대로 쓰면 된다. **test_main.py의 `test_py_subapp_receives_correct_scope`에 `raw_path` 어설션을 추가**해 회귀를 잠근다.

## 완료 조건
- [x] `engine/aimd/main.py`의 서브앱 위임에서 `raw_path` 갱신
- [x] `test_py_subapp_receives_correct_scope`가 `raw_path`도 검증
- [x] `cd engine && uv run pytest tests/test_main.py -q` 통과

## 구현 결과
- **구현 완료 일시**: 2026-08-10T00:59:47-04:00
- **변경 파일**:
  - `engine/aimd/main.py`
  - `engine/tests/test_main.py`
  - `regression-tests/verify-issue-49.sh`
- **계획과의 차이**: 없음
- **검증 결과**: `./regression-tests/verify-issue-49.sh` 통과