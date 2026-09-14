import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_client_chat.dart';
import 'package:hermes_ui/core/api/api_client_cron.dart';
import 'package:hermes_ui/core/api/api_client_git.dart';
import 'package:hermes_ui/core/api/api_client_kanban.dart';
import 'package:hermes_ui/core/api/api_client_memory_skills.dart';
import 'package:hermes_ui/core/api/api_client_server_panels.dart';
import 'package:hermes_ui/core/api/api_client_sessions.dart';
import 'package:hermes_ui/core/api/api_client_upload.dart';
import 'package:hermes_ui/core/api/api_client_workspace.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/models/approval.dart';
import 'package:hermes_ui/core/models/clarification.dart';
import 'package:hermes_ui/core/models/cron.dart';
import 'package:hermes_ui/core/models/git_workspace.dart';
import 'package:hermes_ui/core/models/goal.dart';
import 'package:hermes_ui/core/models/insights.dart';
import 'package:hermes_ui/core/models/kanban.dart';
import 'package:hermes_ui/core/models/memory.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/core/models/server_info.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/core/models/skills.dart';
import 'package:hermes_ui/core/models/transcribe_response.dart';
import 'package:hermes_ui/core/models/upload_response.dart';
import 'package:hermes_ui/core/models/workspace.dart';

void main() {
  const base = 'http://hermes.local:8787';

  ApiClient buildClient(_MockAdapter adapter) {
    final dio = Dio(
      BaseOptions(validateStatus: (_) => true, followRedirects: false),
    );
    dio.httpClientAdapter = adapter;
    final publicDio = Dio(
      BaseOptions(validateStatus: (_) => true, followRedirects: false),
    );
    publicDio.httpClientAdapter = adapter;
    return ApiClient(
      baseUrl: base,
      dio: dio,
      publicMediaDio: publicDio,
    );
  }

  group('ApiClientServer (1.1)', () {
    test('health: typed response + malformed fault-tolerance', () async {
      final adapter = _MockAdapter(
        responder: (_) => ResponseBody.fromString(
          '{"status":"ok","sessions":5,"active_streams":1,"uptime_seconds":123.45}',
          200,
        ),
      );
      final client = buildClient(adapter);
      final res = await client.health();
      expect(res, isA<HealthResponse>());
      expect(res.status, 'ok');
      expect(res.sessions, 5);
      expect(res.activeStreams, 1);
      expect(res.uptimeSeconds, 123.45);

      // Malformed json / missing fields
      adapter.responder = (_) => ResponseBody.fromString('{"unexpected":123}', 200);
      final degraded = await client.health();
      expect(degraded.status, isNull);
      expect(degraded.sessions, isNull);
    });

    test('authStatus: typed response', () async {
      final adapter = _MockAdapter(
        responder: (_) => ResponseBody.fromString(
          '{"auth_enabled":true,"password_auth_enabled":true}',
          200,
        ),
      );
      final client = buildClient(adapter);
      final res = await client.authStatus();
      expect(res, isA<AuthStatusResponse>());
      expect(res.authEnabled, isTrue);
      expect(res.passwordAuthEnabled, isTrue);
    });

    test('login & logout: typed response', () async {
      final adapter = _MockAdapter(
        responder: (_) => ResponseBody.fromString('{"ok":true}', 200),
      );
      final client = buildClient(adapter);
      final loginRes = await client.login('secret');
      expect(loginRes, isA<LoginResponse>());
      expect(loginRes.ok, isTrue);

      final logoutRes = await client.logout();
      expect(logoutRes, isA<LoginResponse>());
      expect(logoutRes.ok, isTrue);
    });
  });

  group('ApiClientSessions & Projects (1.2 & 1.3)', () {
    test('sessions & searchSessions & session & sessionStatus', () async {
      final adapter = _MockAdapter(
        responder: (opt) {
          if (opt.path.contains('/api/sessions/search')) {
            return ResponseBody.fromString('{"sessions":[{"id":"s1","title":"Search 1"}]}', 200);
          }
          if (opt.path.contains('/api/session/status')) {
            return ResponseBody.fromString('{"session_id":"s1","is_streaming":true}', 200);
          }
          if (opt.path.contains('/api/session?')) {
            return ResponseBody.fromString('{"session":{"session_id":"s1","title":"Detail"}}', 200);
          }
          return ResponseBody.fromString('{"sessions":[{"id":"s1","title":"Session 1"}],"archived_count":2}', 200);
        },
      );
      final client = buildClient(adapter);

      final list = await client.sessions(includeArchived: true, archivedLimit: 10);
      expect(list, isA<SessionsResponse>());
      expect(list.sessions?.length, 1);
      expect(list.archivedCount, 2);

      final search = await client.searchSessions(query: 'test');
      expect(search, isA<SessionSearchResponse>());
      expect(search.sessions?.length, 1);

      final sess = await client.session(sessionId: 's1');
      expect(sess, isA<SessionResponse>());
      expect(sess.session?.id, 's1');

      final status = await client.sessionStatus('s1');
      expect(status, isA<SessionStatusResponse>());
      expect(status.sessionId, 's1');
      expect(status.isStreaming, isTrue);
    });

    test('mutations: createSession, rename, delete, pin, archive, branch, compress, undo, retry, truncate, update, move, yolo', () async {
      final adapter = _MockAdapter(
        responder: (opt) {
          if (opt.path.endsWith('/api/session/new')) {
            return ResponseBody.fromString('{"session":{"session_id":"new-1","title":"New"}}', 200);
          }
          if (opt.path.endsWith('/api/session/branch')) {
            return ResponseBody.fromString('{"session_id":"b-1","parent_session_id":"p-1"}', 200);
          }
          if (opt.path.endsWith('/api/session/compress')) {
            return ResponseBody.fromString('{"ok":true,"session":{"id":"c-1"}}', 200);
          }
          if (opt.path.endsWith('/api/session/undo')) {
            return ResponseBody.fromString('{"ok":true}', 200);
          }
          if (opt.path.endsWith('/api/session/retry')) {
            return ResponseBody.fromString('{"ok":true,"last_user_text":"Hello"}', 200);
          }
          if (opt.path.endsWith('/api/session/truncate')) {
            return ResponseBody.fromString('{"session":{"session_id":"t-1"}}', 200);
          }
          if (opt.path.endsWith('/api/session/update')) {
            return ResponseBody.fromString('{"session":{"session_id":"u-1","workspace":"/w"}}', 200);
          }
          if (opt.path.contains('/api/session/yolo')) {
            return ResponseBody.fromString('{"ok":true,"yolo_enabled":true}', 200);
          }
          return ResponseBody.fromString('{"ok":true}', 200);
        },
      );
      final client = buildClient(adapter);

      final created = await client.createSession();
      expect(created.session?.id, 'new-1');

      final renamed = await client.renameSession(sessionId: 's1', title: 'T');
      expect(renamed, isA<SessionMutationResponse>());
      expect(renamed.ok, isTrue);

      final deleted = await client.deleteSession('s1');
      expect(deleted.ok, isTrue);

      final pinned = await client.pinSession(sessionId: 's1', pinned: true);
      expect(pinned.ok, isTrue);

      final archived = await client.archiveSession(sessionId: 's1', archived: true);
      expect(archived.ok, isTrue);

      final branched = await client.branchSession(sessionId: 's1');
      expect(branched, isA<SessionBranchResponse>());
      expect(branched.sessionId, 'b-1');

      final compressed = await client.compressSession(sessionId: 's1');
      expect(compressed, isA<SessionCompressResponse>());
      expect(compressed.ok, isTrue);

      final undone = await client.undoSession('s1');
      expect(undone, isA<SessionUndoResponse>());
      expect(undone.ok, isTrue);

      final retried = await client.retrySession('s1');
      expect(retried, isA<SessionRetryResponse>());
      expect(retried.lastUserText, 'Hello');

      final truncated = await client.truncateSession(sessionId: 's1', keepCount: 2);
      expect(truncated, isA<SessionResponse>());
      expect(truncated.session?.id, 't-1');

      final updated = await client.updateSession(sessionId: 's1', workspace: '/w');
      expect(updated, isA<SessionResponse>());
      expect(updated.session?.workspace, '/w');

      final moved = await client.moveSession(sessionId: 's1', projectId: 'p1');
      expect(moved.ok, isTrue);

      final getYolo = await client.sessionYolo('s1');
      expect(getYolo, isA<SessionYoloResponse>());
      expect(getYolo.yoloEnabled, isTrue);

      final setYolo = await client.setSessionYolo(sessionId: 's1', enabled: true);
      expect(setYolo.yoloEnabled, isTrue);
    });

    test('projects endpoints', () async {
      final adapter = _MockAdapter(
        responder: (opt) {
          if (opt.method == 'GET') {
            return ResponseBody.fromString('{"projects":[{"id":"p1","name":"Proj"}]}', 200);
          }
          return ResponseBody.fromString('{"ok":true,"project":{"id":"p1","name":"Proj"}}', 200);
        },
      );
      final client = buildClient(adapter);

      final projs = await client.projects();
      expect(projs, isA<ProjectsResponse>());
      expect(projs.projects?.length, 1);

      final createP = await client.createProject(name: 'Proj');
      expect(createP, isA<ProjectMutationResponse>());
      expect(createP.ok, isTrue);

      final renameP = await client.renameProject(projectId: 'p1', name: 'NewProj');
      expect(renameP.ok, isTrue);

      final deleteP = await client.deleteProject('p1');
      expect(deleteP.ok, isTrue);
    });
  });

  group('ApiClientChat & Approval & Clarify (1.4, 1.5, 1.6)', () {
    test('chat endpoints: start, cancel, status, steer, goal, btw, background', () async {
      final adapter = _MockAdapter(
        responder: (opt) {
          if (opt.path.endsWith('/api/chat/start')) {
            return ResponseBody.fromString('{"stream_id":"st1","session_id":"s1"}', 200);
          }
          if (opt.path.contains('/api/chat/cancel')) {
            return ResponseBody.fromString('{"ok":true}', 200);
          }
          if (opt.path.contains('/api/chat/stream/status')) {
            return ResponseBody.fromString('{"active":true,"stream_id":"st1"}', 200);
          }
          if (opt.path.endsWith('/api/chat/steer')) {
            return ResponseBody.fromString('{"accepted":true}', 200);
          }
          if (opt.path.endsWith('/api/goal')) {
            return ResponseBody.fromString('{"ok":true,"goal":{"goal":"ship it","status":"active"}}', 200);
          }
          if (opt.path.endsWith('/api/btw')) {
            return ResponseBody.fromString('{"stream_id":"btw-1"}', 200);
          }
          if (opt.path.endsWith('/api/background')) {
            return ResponseBody.fromString('{"stream_id":"bg-1"}', 200);
          }
          if (opt.path.contains('/api/background/status')) {
            return ResponseBody.fromString('{"results":[{"task_id":"t1","status":"running"}]}', 200);
          }
          return ResponseBody.fromString('{"ok":true}', 200);
        },
      );
      final client = buildClient(adapter);

      final start = await client.startChat(sessionId: 's1', message: 'Hi');
      expect(start, isA<ChatStartResponse>());
      expect(start.streamId, 'st1');

      final cancel = await client.cancelChat('st1');
      expect(cancel, isA<ChatCancelResponse>());
      expect(cancel.ok, isTrue);

      final status = await client.chatStreamStatus('st1');
      expect(status, isA<ChatStreamStatusResponse>());
      expect(status.active, isTrue);
      expect(status.streamId, 'st1');

      final steer = await client.steerChat(sessionId: 's1', text: 'turn left');
      expect(steer, isA<ChatSteerResponse>());
      expect(steer.accepted, isTrue);

      final goal = await client.submitGoal(sessionId: 's1', args: 'ship it');
      expect(goal, isA<GoalSubmissionResponse>());
      expect(goal.goal?.goal, 'ship it');

      final btw = await client.startBtw(sessionId: 's1', question: 'q');
      expect(btw, isA<BtwStartResponse>());
      expect(btw.streamId, 'btw-1');

      final bg = await client.startBackground(sessionId: 's1', prompt: 'p');
      expect(bg, isA<BackgroundStartResponse>());
      expect(bg.streamId, 'bg-1');

      final bgStatus = await client.backgroundStatus('s1');
      expect(bgStatus, isA<BackgroundStatusResponse>());
      expect(bgStatus.results?.first.taskId, 't1');
    });

    test('approval & clarify endpoints', () async {
      final adapter = _MockAdapter(
        responder: (opt) {
          if (opt.path.contains('/api/approval/pending')) {
            return ResponseBody.fromString('{"pending":{"description":"Proceed?","command":"ls"}}', 200);
          }
          if (opt.path.endsWith('/api/approval/respond')) {
            return ResponseBody.fromString('{"ok":true}', 200);
          }
          if (opt.path.contains('/api/clarify/pending')) {
            return ResponseBody.fromString('{"pending":{"question":"Which one?"}}', 200);
          }
          if (opt.path.endsWith('/api/clarify/respond')) {
            return ResponseBody.fromString('{"ok":true}', 200);
          }
          return ResponseBody.fromString('{"ok":true}', 200);
        },
      );
      final client = buildClient(adapter);

      final appPending = await client.approvalPending('s1');
      expect(appPending, isA<ApprovalPendingResponse>());
      expect(appPending.pending?.description, 'Proceed?');

      final appRespond = await client.respondApproval(sessionId: 's1', choice: 'y');
      expect(appRespond, isA<ApprovalRespondResponse>());
      expect(appRespond.ok, isTrue);

      final clarifyPending = await client.clarifyPending('s1');
      expect(clarifyPending, isA<ClarificationPendingResponse>());
      expect(clarifyPending.pending?.question, 'Which one?');

      final clarifyRespond = await client.respondClarification(sessionId: 's1', response: 'this');
      expect(clarifyRespond, isA<ClarificationRespondResponse>());
      expect(clarifyRespond.ok, isTrue);
    });
  });

  group('ApiClientCron (1.12)', () {
    test('cron list, mutation, status, output, delivery options', () async {
      final adapter = _MockAdapter(
        responder: (opt) {
          if (opt.path.endsWith('/api/crons')) {
            return ResponseBody.fromString('{"jobs":[{"id":"j1","name":"Daily Job","schedule":"0 0 * * *"}]}', 200);
          }
          if (opt.path.contains('/api/crons/status')) {
            return ResponseBody.fromString('{"running":true,"job_id":"j1"}', 200);
          }
          if (opt.path.contains('/api/crons/output')) {
            return ResponseBody.fromString('{"outputs":[{"filename":"out.txt","content":"Job ran successfully"}]}', 200);
          }
          if (opt.path.endsWith('/api/crons/delivery-options')) {
            return ResponseBody.fromString('{"platforms":[{"value":"email","label":"Email"}]}', 200);
          }
          return ResponseBody.fromString('{"ok":true}', 200);
        },
      );
      final client = buildClient(adapter);

      final jobs = await client.crons();
      expect(jobs, isA<CronJobsResponse>());
      expect(jobs.jobs?.length, 1);
      expect(jobs.jobs?.first.name, 'Daily Job');

      final create = await client.createCron(
        prompt: 'do work',
        schedule: '0 0 * * *',
        toastNotifications: true,
      );
      expect(create, isA<CronMutationResponse>());
      expect(create.ok, isTrue);

      final update = await client.updateCron(jobId: 'j1', prompt: 'new prompt');
      expect(update.ok, isTrue);

      final del = await client.deleteCron('j1');
      expect(del.ok, isTrue);

      final run = await client.runCron('j1');
      expect(run.ok, isTrue);

      final pause = await client.pauseCron('j1');
      expect(pause.ok, isTrue);

      final resume = await client.resumeCron('j1');
      expect(resume.ok, isTrue);

      final status = await client.cronStatus('j1');
      expect(status, isA<CronStatusResponse>());
      expect(status.running, isTrue);

      final output = await client.cronOutput('j1');
      expect(output, isA<CronOutputResponse>());
      expect(output.outputs?.first.content, 'Job ran successfully');

      final delivery = await client.cronDeliveryOptions();
      expect(delivery, isA<CronDeliveryOptionsResponse>());
      expect(delivery.platforms?.first.value, 'email');
    });
  });

  group('ApiClientGit (1.8)', () {
    test('git endpoints: info, status, branches, diff, remote, checkout, mutation, commit, message', () async {
      final adapter = _MockAdapter(
        responder: (opt) {
          if (opt.path.contains('/api/git-info')) {
            return ResponseBody.fromString('{"git":{"is_git":true,"branch":"main"}}', 200);
          }
          if (opt.path.contains('/api/git/status')) {
            return ResponseBody.fromString('{"git":{"staged":[],"unstaged":[]}}', 200);
          }
          if (opt.path.contains('/api/git/branches')) {
            return ResponseBody.fromString('{"branches":{"current":"main","local":[{"name":"main"}]}}', 200);
          }
          if (opt.path.contains('/api/git/diff')) {
            return ResponseBody.fromString('{"diff":{"diff":"+ added line"}}', 200);
          }
          if (opt.path.endsWith('/api/git/checkout') || opt.path.endsWith('/api/git/stash-checkout')) {
            return ResponseBody.fromString('{"ok":true,"current_branch":"main"}', 200);
          }
          if (opt.path.endsWith('/api/git/commit') || opt.path.endsWith('/api/git/commit-selected')) {
            return ResponseBody.fromString('{"ok":true,"commit":"abc1234"}', 200);
          }
          if (opt.path.endsWith('/api/git/commit-message') || opt.path.endsWith('/api/git/commit-message-selected')) {
            return ResponseBody.fromString('{"ok":true,"message":"feat: new feature"}', 200);
          }
          return ResponseBody.fromString('{"ok":true}', 200);
        },
      );
      final client = buildClient(adapter);

      final info = await client.gitInfo('s1');
      expect(info, isA<GitInfoResponse>());
      expect(info.git?.isGit, isTrue);

      final status = await client.gitStatus('s1');
      expect(status, isA<GitStatusResponse>());
      expect(status.git, isNotNull);

      final branches = await client.gitBranches('s1');
      expect(branches, isA<GitBranchesResponse>());
      expect(branches.branches?.current, 'main');

      final diff = await client.gitDiff(sessionId: 's1', path: 'a.txt');
      expect(diff, isA<GitDiffResponse>());
      expect(diff.diff?.diff, '+ added line');

      final fetch = await client.gitFetch('s1');
      expect(fetch, isA<GitRemoteActionResponse>());
      expect(fetch.ok, isTrue);

      final pull = await client.gitPull('s1');
      expect(pull.ok, isTrue);

      final push = await client.gitPush('s1');
      expect(push.ok, isTrue);

      final co = await client.gitCheckout(sessionId: 's1', ref: 'main');
      expect(co, isA<GitCheckoutResponse>());
      expect(co.ok, isTrue);
      expect(co.currentBranch, 'main');

      final sco = await client.gitStashCheckout(sessionId: 's1', ref: 'main');
      expect(sco, isA<GitCheckoutResponse>());
      expect(sco.ok, isTrue);
      expect(sco.currentBranch, 'main');

      final stage = await client.gitStage(sessionId: 's1', paths: ['a.txt']);
      expect(stage, isA<GitMutationResponse>());
      expect(stage.ok, isTrue);

      final unstage = await client.gitUnstage(sessionId: 's1', paths: ['a.txt']);
      expect(unstage.ok, isTrue);

      final discard = await client.gitDiscard(sessionId: 's1', paths: ['a.txt']);
      expect(discard.ok, isTrue);

      final commit = await client.gitCommit(sessionId: 's1', message: 'm');
      expect(commit, isA<GitCommitResponse>());
      expect(commit.commit, 'abc1234');

      final commitSel = await client.gitCommitSelected(sessionId: 's1', message: 'm', paths: ['a.txt']);
      expect(commitSel.commit, 'abc1234');

      final msg = await client.gitCommitMessage('s1');
      expect(msg, isA<GitCommitMessageResponse>());
      expect(msg.message, 'feat: new feature');

      final msgSel = await client.gitCommitMessageSelected(sessionId: 's1', paths: ['a.txt']);
      expect(msgSel.message, 'feat: new feature');
    });
  });

  group('ApiClientKanban (1.13)', () {
    test('kanban configuration, boards, board snapshot, card detail, dispatch, worker log', () async {
      final adapter = _MockAdapter(
        responder: (opt) {
          if (opt.path.endsWith('/api/kanban/config')) {
            return ResponseBody.fromString('{"columns":["todo","in_progress","done"],"read_only":false}', 200, headers: {'content-type': ['application/json']});
          }
          if (opt.path.endsWith('/api/kanban/boards') && opt.method == 'GET') {
            return ResponseBody.fromString('{"boards":[{"slug":"b1","name":"Board 1"}]}', 200, headers: {'content-type': ['application/json']});
          }
          if (opt.path.contains('/api/kanban/board?')) {
            return ResponseBody.fromString('{"columns":[{"name":"todo","tasks":[{"id":"c1","title":"Card 1"}]}]}', 200, headers: {'content-type': ['application/json']});
          }
          if (opt.path.contains('/api/kanban/stats')) {
            return ResponseBody.fromString('{"total":5,"completed":3}', 200, headers: {'content-type': ['application/json']});
          }
          if (opt.path.contains('/api/kanban/assignees')) {
            return ResponseBody.fromString('{"assignees":["alice","bob"]}', 200, headers: {'content-type': ['application/json']});
          }
          if (opt.path.contains('/api/kanban/events?')) {
            return ResponseBody.fromString('{"events":[{"id":"e1","type":"create"}]}', 200, headers: {'content-type': ['application/json']});
          }
          if (opt.path.contains('/api/kanban/tasks/c1/log')) {
            return ResponseBody.fromString('{"content":"worker finished","exists":true}', 200, headers: {'content-type': ['application/json']});
          }
          if (opt.path.contains('/api/kanban/tasks/c1/comments')) {
            return ResponseBody.fromString('{"ok":true,"comment_id":"cm1"}', 200, headers: {'content-type': ['application/json']});
          }
          if (opt.path.contains('/api/kanban/tasks/c1') && !opt.path.contains('comments') && !opt.path.contains('log')) {
            return ResponseBody.fromString('{"task":{"id":"c1","title":"Card 1"}}', 200, headers: {'content-type': ['application/json']});
          }
          if (opt.path.contains('/api/kanban/tasks') && !opt.path.contains('/tasks/') && !opt.path.contains('/bulk') && opt.method == 'POST') {
            return ResponseBody.fromString('{"task":{"id":"c2","title":"Card 2"}}', 200, headers: {'content-type': ['application/json']});
          }
          if (opt.path.endsWith('/api/kanban/tasks/bulk')) {
            return ResponseBody.fromString('{"modified":3}', 200, headers: {'content-type': ['application/json']});
          }
          if (opt.path.contains('/api/kanban/links')) {
            return ResponseBody.fromString('{"ok":true}', 200, headers: {'content-type': ['application/json']});
          }
          if (opt.path.contains('/api/kanban/dispatch')) {
            return ResponseBody.fromString('{"spawned":2,"promoted":1}', 200, headers: {'content-type': ['application/json']});
          }
          return ResponseBody.fromString('{"ok":true}', 200, headers: {'content-type': ['application/json']});
        },
      );
      final client = buildClient(adapter);

      final cfg = await client.kanbanConfiguration();
      expect(cfg, isA<KanbanConfiguration>());
      expect(cfg.columns, ['todo', 'in_progress', 'done']);

      final boards = await client.kanbanBoards();
      expect(boards, isA<KanbanBoardsResponse>());
      expect(boards.boards?.length, 1);

      final createdBoard = await client.createKanbanBoard(
        slug: 'b2',
        name: 'B2',
        description: 'd',
        icon: 'i',
        color: 'c',
      );
      expect(createdBoard, isA<KanbanBoardMutationEnvelope>());

      final editedBoard = await client.editKanbanBoard(
        slug: 'b2',
        name: 'B2 edited',
        description: 'd',
        icon: 'i',
        color: 'c',
      );
      expect(editedBoard, isA<KanbanBoardMutationEnvelope>());

      final archivedBoard = await client.archiveKanbanBoard('b2');
      expect(archivedBoard, isA<KanbanBoardMutationEnvelope>());

      final activeBoard = await client.makeKanbanBoardActive('b1');
      expect(activeBoard, isA<KanbanBoardMutationEnvelope>());

      final snap = await client.kanbanBoard(board: 'b1');
      expect(snap, isA<KanbanBoardSnapshot>());
      expect(snap.columns?.first.cards?.length, 1);

      final stats = await client.kanbanStats('b1');
      expect(stats, isA<KanbanStats>());
      expect(stats.total, 5);

      final assignees = await client.kanbanAssignees('b1');
      expect(assignees, isA<KanbanAssigneeHistory>());
      expect(assignees.assignees, ['alice', 'bob']);

      final events = await client.kanbanEvents(board: 'b1', since: 0);
      expect(events, isA<KanbanEventsEnvelope>());
      expect(events.events?.length, 1);

      final cardDetail = await client.kanbanCardDetail(board: 'b1', cardId: 'c1');
      expect(cardDetail, isA<KanbanCardDetailEnvelope>());
      expect(cardDetail.card?.title, 'Card 1');

      final workerLog = await client.kanbanWorkerLog(board: 'b1', cardId: 'c1');
      expect(workerLog, isA<KanbanWorkerLog>());
      expect(workerLog.content, 'worker finished');

      final comment = await client.addKanbanComment(board: 'b1', cardId: 'c1', body: 'Nice');
      expect(comment, isA<KanbanAddCommentResponse>());
      expect(comment.ok, isTrue);

      final newCard = await client.createKanbanCard(
        board: 'b1',
        title: 'Card 2',
        status: 'todo',
        workspaceKind: 'project',
        idempotencyKey: 'k1',
      );
      expect(newCard, isA<KanbanCardMutationEnvelope>());
      expect(newCard.card?.title, 'Card 2');

      final bulk = await client.performKanbanBulkAction(board: 'b1', ids: ['c1', 'c2'], archive: true);
      expect(bulk, isA<KanbanBulkActionEnvelope>());

      final editCard = await client.editKanbanCard(
        board: 'b1',
        cardId: 'c1',
        title: 'New Title',
        body: 'New Body',
        tenant: null,
        priority: 1,
        assignee: null,
      );
      expect(editCard, isA<KanbanCardMutationEnvelope>());

      final setStatus = await client.setKanbanCardStatus(board: 'b1', cardId: 'c1', status: 'done');
      expect(setStatus, isA<KanbanCardMutationEnvelope>());

      final block = await client.blockKanbanCard(board: 'b1', cardId: 'c1');
      expect(block, isA<KanbanCardMutationEnvelope>());

      final unblock = await client.unblockKanbanCard(board: 'b1', cardId: 'c1');
      expect(unblock, isA<KanbanCardMutationEnvelope>());

      final addDep = await client.addKanbanDependency(board: 'b1', parentId: 'c1', childId: 'c2');
      expect(addDep, isA<KanbanDependencyMutationEnvelope>());

      final remDep = await client.removeKanbanDependency(board: 'b1', parentId: 'c1', childId: 'c2');
      expect(remDep, isA<KanbanDependencyMutationEnvelope>());

      final dispatch = await client.dispatchKanban(board: 'b1');
      expect(dispatch, isA<KanbanDispatchResult>());
      expect(dispatch.spawned, 2);
    });

    test('kanban guards: non-json content-type & running status guard & empty dispatch categories', () async {
      final adapter = _MockAdapter(
        responder: (_) => ResponseBody.fromString(
          '<html>Not JSON</html>',
          200,
          headers: {'content-type': ['text/html']},
        ),
      );
      final client = buildClient(adapter);

      await expectLater(
        client.kanbanConfiguration(),
        throwsA(isA<KanbanNonJsonContentTypeException>()),
      );

      // Running status guard throws locally
      await expectLater(
        client.setKanbanCardStatus(board: 'b1', cardId: 'c1', status: 'running'),
        throwsA(isA<KanbanRunningStatusRequiresDispatcherException>()),
      );

      // Dispatch with no recognized categories throws
      adapter.responder = (_) => ResponseBody.fromString(
        '{"unknown_key": 1}',
        200,
        headers: {'content-type': ['application/json']},
      );
      await expectLater(
        client.dispatchKanban(board: 'b1'),
        throwsA(isA<KanbanDispatchMissingResultException>()),
      );
    });
  });

  group('ApiClientMemorySkills (1.14 & 1.15)', () {
    test('memory & writeMemory & skills & skillContent & toggleSkill', () async {
      final adapter = _MockAdapter(
        responder: (opt) {
          if (opt.path.endsWith('/api/memory') && opt.method == 'GET') {
            return ResponseBody.fromString('{"memory":"user likes dart","soul":"helpful assistant"}', 200);
          }
          if (opt.path.endsWith('/api/memory/write')) {
            return ResponseBody.fromString('{"ok":true,"section":"memory","path":"/m"}', 200);
          }
          if (opt.path.endsWith('/api/skills')) {
            return ResponseBody.fromString('{"skills":[{"name":"flutter","category":"code"}]}', 200);
          }
          if (opt.path.contains('/api/skills/content')) {
            return ResponseBody.fromString('{"name":"flutter","content":"info"}', 200);
          }
          if (opt.path.endsWith('/api/skills/toggle')) {
            return ResponseBody.fromString('{"ok":true,"name":"flutter","enabled":true}', 200);
          }
          return ResponseBody.fromString('{"ok":true}', 200);
        },
      );
      final client = buildClient(adapter);

      final mem = await client.memory();
      expect(mem, isA<MemoryResponse>());
      expect(mem.memory, 'user likes dart');

      final memWrite = await client.writeMemory(section: 'memory', content: 'new info');
      expect(memWrite, isA<MemoryWriteResponse>());
      expect(memWrite.ok, isTrue);

      final sks = await client.skills();
      expect(sks, isA<SkillsResponse>());
      expect(sks.skills?.first.name, 'flutter');

      final content = await client.skillContent(name: 'flutter');
      expect(content, isA<SkillDetailResponse>());
      expect(content.content, 'info');

      final toggled = await client.toggleSkill(name: 'flutter', enabled: true);
      expect(toggled, isA<ToggleSkillResponse>());
      expect(toggled.enabled, isTrue);
    });
  });

  group('ApiClientServerPanels (1.9, 1.10, 1.11)', () {
    test('models, commands, reasoning, providers, settings, updates, profiles, insights', () async {
      final adapter = _MockAdapter(
        responder: (opt) {
          if (opt.path.endsWith('/api/models')) {
            return ResponseBody.fromString('{"groups":[{"name":"OpenAI","models":[{"id":"gpt-4"}]}]}', 200);
          }
          if (opt.path.endsWith('/api/models/live')) {
            return ResponseBody.fromString('{"models":[{"id":"live-1"}]}', 200);
          }
          if (opt.path.endsWith('/api/commands')) {
            return ResponseBody.fromString('{"commands":[{"name":"/help","description":"help text"}]}', 200);
          }
          if (opt.path.endsWith('/api/default-model')) {
            return ResponseBody.fromString('{"default_model":"gpt-4"}', 200);
          }
          if (opt.path.contains('/api/reasoning')) {
            return ResponseBody.fromString('{"effort":"high","supported_efforts":["low","high"]}', 200);
          }
          if (opt.path.endsWith('/api/providers')) {
            return ResponseBody.fromString('{"providers":[{"id":"p1","name":"Provider 1"}]}', 200);
          }
          if (opt.path.endsWith('/api/settings')) {
            return ResponseBody.fromString('{"show_cli_sessions":true}', 200);
          }
          if (opt.path.endsWith('/api/updates/check')) {
            return ResponseBody.fromString('{"has_update":true,"latest_version":"2.0"}', 200);
          }
          if (opt.path.endsWith('/api/updates/apply')) {
            return ResponseBody.fromString('{"ok":true,"restarting":true}', 200);
          }
          if (opt.path.endsWith('/api/personalities')) {
            return ResponseBody.fromString('{"personalities":[{"id":"p1","name":"Coder"}]}', 200);
          }
          if (opt.path.endsWith('/api/personality/set')) {
            return ResponseBody.fromString('{"ok":true}', 200);
          }
          if (opt.path.endsWith('/api/profiles') && opt.method == 'GET') {
            return ResponseBody.fromString('{"profiles":[{"name":"Default"}],"active":"Default"}', 200);
          }
          if (opt.path.endsWith('/api/profile/switch')) {
            return ResponseBody.fromString('{"ok":true,"active":"Default"}', 200);
          }
          if (opt.path.endsWith('/api/profile/create')) {
            return ResponseBody.fromString('{"ok":true,"name":"NewProf"}', 200);
          }
          if (opt.path.contains('/api/insights')) {
            return ResponseBody.fromString('{"period_days":7,"total_tokens":1000}', 200);
          }
          return ResponseBody.fromString('{"ok":true}', 200);
        },
      );
      final client = buildClient(adapter);

      final mdls = await client.models();
      expect(mdls, isA<ModelsResponse>());
      expect(mdls.catalogGroups.first.models.first.id, 'gpt-4');

      final live = await client.modelsLive();
      expect(live, isA<ModelsLiveResponse>());

      final cmds = await client.commands();
      expect(cmds, isA<CommandsResponse>());

      final defMdl = await client.saveDefaultModel('gpt-4');
      expect(defMdl, isA<DefaultModelResponse>());

      final rStatus = await client.reasoning();
      expect(rStatus, isA<ReasoningStatusResponse>());
      expect(rStatus.effort, 'high');

      final saveEffort = await client.saveReasoningEffort('low');
      expect(saveEffort, isA<ReasoningStatusResponse>());

      final saveDisplay = await client.saveReasoningDisplay('compact');
      expect(saveDisplay, isA<ReasoningStatusResponse>());

      final provs = await client.providers();
      expect(provs, isA<ProvidersResponse>());

      final sett = await client.settings();
      expect(sett, isA<SettingsResponse>());

      final cliSett = await client.updateSettingsShowCliSessions(true);
      expect(cliSett, isA<SettingsResponse>());

      final claudeSett = await client.updateSettingsShowClaudeCodeSessions(true);
      expect(claudeSett, isA<SettingsResponse>());

      final upCheck = await client.updatesCheck();
      expect(upCheck, isA<UpdatesCheckResponse>());

      final upForced = await client.updatesCheckForced();
      expect(upForced, isA<UpdatesCheckResponse>());

      final upApply = await client.applyUpdate();
      expect(upApply, isA<UpdatesApplyResponse>());

      final pers = await client.personalities();
      expect(pers, isA<PersonalitiesResponse>());

      final setPers = await client.setPersonality(sessionId: 's1', name: 'Coder');
      expect(setPers, isA<PersonalitySetResponse>());

      final profs = await client.profiles();
      expect(profs, isA<ProfilesResponse>());

      final swProf = await client.switchProfile('Default');
      expect(swProf, isA<ProfileSwitchResponse>());

      final crProf = await client.createProfile(name: 'NewProf');
      expect(crProf, isA<ProfileCreateResponse>());

      final ins = await client.insights(7);
      expect(ins, isA<InsightsResponse>());
      expect(ins.periodDays, 7);
      expect(ins.totalTokens, 1000);
    });
  });

  group('ApiClientWorkspace (1.7)', () {
    test('workspace methods: list, suggest, add, remove, rename, reorder, directoryList, file, delete, rename', () async {
      final adapter = _MockAdapter(
        responder: (opt) {
          if (opt.path.endsWith('/api/workspaces') && opt.method == 'GET') {
            return ResponseBody.fromString('{"workspaces":[{"path":"/w1","name":"W1"}]}', 200);
          }
          if (opt.path.contains('/api/workspaces/suggest')) {
            return ResponseBody.fromString('{"suggestions":["/home/user/project"]}', 200);
          }
          if (opt.path.contains('/api/list')) {
            return ResponseBody.fromString('{"entries":[{"name":"a.txt","is_file":true,"size":100}]}', 200);
          }
          if (opt.path.contains('/api/file?')) {
            return ResponseBody.fromString('{"name":"a.txt","content":"hello world","size":11}', 200);
          }
          if (opt.path.endsWith('/api/file/delete')) {
            return ResponseBody.fromString('{"ok":true,"path":"a.txt"}', 200);
          }
          if (opt.path.endsWith('/api/file/rename')) {
            return ResponseBody.fromString('{"ok":true,"old_path":"a.txt","new_path":"b.txt"}', 200);
          }
          return ResponseBody.fromString('{"ok":true,"workspaces":[{"path":"/w1"}]}', 200);
        },
      );
      final client = buildClient(adapter);

      final ws = await client.workspaces();
      expect(ws, isA<WorkspacesResponse>());
      expect(ws.workspaces?.length, 1);

      final sugg = await client.workspaceSuggestions('/home');
      expect(sugg, isA<WorkspaceSuggestionsResponse>());
      expect(sugg.suggestions?.first, '/home/user/project');

      final add = await client.addWorkspace(path: '/w2');
      expect(add, isA<WorkspaceMutationResponse>());
      expect(add.ok, isTrue);

      final rem = await client.removeWorkspace('/w2');
      expect(rem.ok, isTrue);

      final ren = await client.renameWorkspace(path: '/w2', name: 'NewW');
      expect(ren.ok, isTrue);

      final reord = await client.reorderWorkspaces(['/w2', '/w1']);
      expect(reord.ok, isTrue);

      final dir = await client.directoryList(sessionId: 's1');
      expect(dir, isA<DirectoryListResponse>());
      expect(dir.entries?.length, 1);

      final f = await client.file(sessionId: 's1', path: 'a.txt');
      expect(f, isA<FileResponse>());
      expect(f.content, 'hello world');

      final delF = await client.deleteFile(sessionId: 's1', path: 'a.txt');
      expect(delF, isA<FileDeleteResponse>());
      expect(delF.ok, isTrue);

      final renF = await client.renameFile(sessionId: 's1', path: 'a.txt', newName: 'b.txt');
      expect(renF, isA<FileRenameResponse>());
      expect(renF.oldPath, 'a.txt');
      expect(renF.newPath, 'b.txt');
    });
  });

  group('ApiClientUpload & Transcribe & TTS (1.16)', () {
    test('uploadFile & transcribeAudio & synthesizeSpeech', () async {
      final adapter = _MockAdapter(
        responder: (opt) {
          if (opt.path.endsWith('/api/upload')) {
            return ResponseBody.fromString('{"filename":"test.png","path":"/p/test.png","size":128,"is_image":true}', 200);
          }
          if (opt.path.endsWith('/api/transcribe')) {
            return ResponseBody.fromString('{"ok":true,"transcript":"speech to text result"}', 200);
          }
          if (opt.path.endsWith('/api/tts')) {
            return ResponseBody.fromString('mp3-audio-bytes', 200);
          }
          return ResponseBody.fromString('{}', 200);
        },
      );
      final client = buildClient(adapter);

      final uploaded = await client.uploadFile(
        sessionId: 's1',
        filename: 'test.png',
        data: Uint8List.fromList([1, 2, 3]),
      );
      expect(uploaded, isA<UploadResponse>());
      expect(uploaded.filename, 'test.png');
      expect(uploaded.isImage, isTrue);

      final transcribed = await client.transcribeAudio(
        filename: 'audio.wav',
        data: Uint8List.fromList([4, 5, 6]),
      );
      expect(transcribed, isA<TranscribeResponse>());
      expect(transcribed.transcript, 'speech to text result');

      final speech = await client.synthesizeSpeech(text: 'Hello', voice: 'alloy');
      expect(String.fromCharCodes(speech), 'mp3-audio-bytes');
    });

    test('uploadFile > 20MB triggers local validation error', () async {
      final adapter = _MockAdapter(responder: (_) => ResponseBody.fromString('{}', 200));
      final client = buildClient(adapter);
      final hugeData = Uint8List(20 * 1024 * 1024 + 1);

      await expectLater(
        client.uploadFile(sessionId: 's1', filename: 'big.zip', data: hugeData),
        throwsA(isA<UploadFileTooLargeException>()),
      );
    });

    test('transcribeAudio decodes error JSON even on non-200 status', () async {
      final adapter = _MockAdapter(
        responder: (_) => ResponseBody.fromString('{"ok":false,"error":"Service Unavailable"}', 503),
      );
      final client = buildClient(adapter);

      final res = await client.transcribeAudio(
        filename: 'a.wav',
        data: Uint8List.fromList([1, 2]),
      );
      expect(res, isA<TranscribeResponse>());
      expect(res.ok, isFalse);
      expect(res.error, 'Service Unavailable');
    });
  });
  group('ApiClientSessions 列表超时与并发去重 (#111)', () {
    test('sessions 列表请求 receiveTimeout 放宽至 120s（其余端点仍 60s）', () async {
      final adapter = _MockAdapter(
        responder: (_) => ResponseBody.fromString('{"sessions":[]}', 200),
      );
      final client = buildClient(adapter);
      await client.sessions();
      expect(adapter.requests, hasLength(1));
      expect(
        adapter.requests.single.receiveTimeout,
        const Duration(seconds: 120),
      );
      // 旁证：其它域端点未被顺手放宽。
      await client.projects();
      expect(adapter.requests.last.receiveTimeout, isNot(
        const Duration(seconds: 120),
      ));
    });

    test('并发 sessions 请求合并为一次网络往返；在途注销后重新发起', () async {
      final adapter = _MockAdapter(
        responder: (_) => ResponseBody.fromString(
          '{"sessions":[{"session_id":"s1","title":"Session 1"}]}',
          200,
        ),
      );
      final client = buildClient(adapter);

      // 冷启动并发两路（会话列表 + 托盘菜单）：共享同一个在途 Future。
      final first = client.sessions();
      final second = client.sessions();
      expect(identical(first, second), isTrue);

      final results = await Future.wait([first, second]);
      expect(adapter.requests, hasLength(1));
      expect(results[0].sessions?.single.sessionId, 's1');
      expect(results[1].sessions?.single.sessionId, 's1');

      // 在途请求结束后（成功或失败）登记注销 → 再调发新请求。
      await client.sessions();
      expect(adapter.requests, hasLength(2));
    });

    test('并发去重的失败同样共享，且不产生未处理异步异常', () async {
      final adapter = _MockAdapter(
        responder: (_) => ResponseBody.fromString('boom', 500),
      );
      final client = buildClient(adapter);
      final first = client.sessions();
      final second = client.sessions();
      await expectLater(first, throwsA(isA<ApiException>()));
      await expectLater(second, throwsA(isA<ApiException>()));
      expect(adapter.requests, hasLength(1));
    });

    test('不同参数的 sessions 请求不互相去重', () async {
      final adapter = _MockAdapter(
        responder: (_) => ResponseBody.fromString('{"sessions":[]}', 200),
      );
      final client = buildClient(adapter);
      await Future.wait([
        client.sessions(),
        client.sessions(includeArchived: true, archivedLimit: 10),
      ]);
      expect(adapter.requests, hasLength(2));
    });
  });

}

class _MockAdapter implements HttpClientAdapter {
  _MockAdapter({required this.responder});

  ResponseBody Function(RequestOptions options) responder;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}
