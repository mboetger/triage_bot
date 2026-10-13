import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

class BranchInfo {
  BranchInfo({
    required this.name,
    required this.compareUrl,
    required this.repository,
  });
  final String name;
  final String compareUrl;
  final String repository;
}

class RepoTarget {
  const RepoTarget({
    required this.owner,
    required this.repo,
    required this.upstreamOwner,
    required this.upstreamRepo,
    required this.upstreamBranch,
  });

  final String owner;
  final String repo;
  final String upstreamOwner;
  final String upstreamRepo;
  final String upstreamBranch;

  String get fullName => '$owner/$repo';
  String get upstreamFullName => '$upstreamOwner/$upstreamRepo';
}

const targetRepositories = [
  RepoTarget(
    owner: 'mboetger',
    repo: 'flutter',
    upstreamOwner: 'flutter',
    upstreamRepo: 'flutter',
    upstreamBranch: 'master',
  ),
  RepoTarget(
    owner: 'mboetger',
    repo: 'packages',
    upstreamOwner: 'flutter',
    upstreamRepo: 'packages',
    upstreamBranch: 'main',
  ),
];

class Home extends StatefulComponent {
  const Home({super.key});

  @override
  State<Home> createState() => HomeState();
}

class HomeState extends State<Home> {
  String issueId = '';
  String searchedIssueId = '';
  bool isLoading = false;
  String status = '';
  List<BranchInfo> matchingBranches = [];
  DateTime? lastCheckTime;
  int? totalTriageIssues;
  List<String> last20Issues = [];

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      try {
        final uri = Uri.parse(web.window.location.href);
        // Support ?issue=12345 or ?id=12345 in the URL
        final param = uri.queryParameters['issue'] ?? uri.queryParameters['id'];
        if (param != null && param.isNotEmpty) {
          issueId = param;
        }
      } catch (_) {}
    }
    _fetchTotalTriageIssues();
  }

  Future<void> _fetchTotalTriageIssues() async {
    try {
      int count = 0;
      final Set<int> issueNumbers = {};

      final responses = await Future.wait(
        targetRepositories.map(
          (target) => http.get(
            Uri.parse('https://api.github.com/repos/${target.fullName}/git/matching-refs/heads/triage-issue-'),
          ),
        ),
      );

      for (final response in responses) {
        if (response.statusCode == 200) {
          final List<dynamic> data = jsonDecode(response.body);
          for (final item in data) {
            final ref = item['ref'] as String?;
            if (ref != null && ref.startsWith('refs/heads/triage-issue-')) {
              count++;
              final match = RegExp(r'triage-issue-(\d+)').firstMatch(ref);
              if (match != null) {
                issueNumbers.add(int.parse(match.group(1)!));
              }
            }
          }
        }
      }

      final sortedIssues = issueNumbers.toList()..sort((first, second) => second.compareTo(first));
      final top20 = sortedIssues.take(20).map((id) => id.toString()).toList();

      if (mounted) {
        setState(() {
          totalTriageIssues = count;
          last20Issues = top20;
        });
      }
    } catch (_) {}
  }

  Future<void> checkIssue() async {
    final cleanId = issueId.trim().replaceAll('#', '');
    if (cleanId.isEmpty) return;

    // Client-side throttling: prevent requests more than once every 2 seconds
    final now = DateTime.now();
    if (lastCheckTime != null && now.difference(lastCheckTime!) < const Duration(seconds: 2)) {
      return;
    }
    lastCheckTime = now;

    setState(() {
      isLoading = true;
      status = '';
      matchingBranches = [];
      searchedIssueId = cleanId;
    });

    try {
      bool isRateLimited = false;
      final branchInfos = <BranchInfo>[];

      // Query all target repositories in parallel
      final repoResponses = await Future.wait(
        targetRepositories.map((target) async {
          final url = Uri.parse(
            'https://api.github.com/repos/${target.fullName}/git/matching-refs/heads/triage-issue-$cleanId',
          );
          final response = await http.get(url);
          return (target: target, response: response);
        }),
      );

      for (final item in repoResponses) {
        final target = item.target;
        final response = item.response;

        if (response.statusCode == 403 || response.statusCode == 429) {
          isRateLimited = true;
          continue;
        }

        if (response.statusCode == 200) {
          final List<dynamic> data = jsonDecode(response.body);
          for (final refItem in data) {
            final ref = refItem['ref'] as String?;
            if (ref != null && ref.startsWith('refs/heads/')) {
              final branchName = ref.substring('refs/heads/'.length);

              // Fetch the merge base commit SHA against upstream repo
              // (e.g. flutter/flutter:master or flutter/packages:main)
              // because mboetger fork branches may be far behind upstream.
              String baseSha = '';
              try {
                final compareUrl = Uri.parse(
                  'https://api.github.com/repos/${target.upstreamFullName}/compare/${target.upstreamBranch}...${target.owner}:$branchName',
                );
                final compareRes = await http.get(compareUrl);
                if (compareRes.statusCode == 200) {
                  final compareData = jsonDecode(compareRes.body);
                  baseSha = compareData['merge_base_commit']['sha'] as String;
                } else {
                  final compareUrlFallback = Uri.parse(
                    'https://api.github.com/repos/${target.fullName}/compare/${target.upstreamOwner}:${target.upstreamBranch}...$branchName',
                  );
                  final compareResFallback = await http.get(compareUrlFallback);
                  if (compareResFallback.statusCode == 200) {
                    final compareDataFallback = jsonDecode(compareResFallback.body);
                    baseSha = compareDataFallback['merge_base_commit']['sha'] as String;
                  }
                }
              } catch (_) {}

              final finalCompareUrl = baseSha.isNotEmpty
                  ? 'https://github.com/${target.fullName}/compare/$baseSha...$branchName'
                  : 'https://github.com/${target.fullName}/compare/$branchName';

              branchInfos.add(
                BranchInfo(
                  name: branchName,
                  compareUrl: finalCompareUrl,
                  repository: target.fullName,
                ),
              );
            }
          }
        }
      }

      if (isRateLimited && branchInfos.isEmpty) {
        setState(() {
          isLoading = false;
          status = 'RateLimited';
          matchingBranches = [];
        });
        return;
      }

      if (branchInfos.isNotEmpty) {
        setState(() {
          isLoading = false;
          status = 'Found';
          matchingBranches = branchInfos;
        });
      } else {
        setState(() {
          isLoading = false;
          status = 'Not triaged';
          matchingBranches = [];
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        status = 'Not triaged';
        matchingBranches = [];
      });
    }
  }

  @override
  Component build(BuildContext context) {
    return div(classes: 'glass-card', [
      div(classes: 'header', [
        div(classes: 'logo-container', [
          // Git branch SVG icon
          .element(tag: 'svg', classes: 'logo-icon', attributes: {
            'xmlns': 'http://www.w3.org/2000/svg',
            'viewBox': '0 0 24 24',
            'fill': 'none',
            'stroke': 'currentColor',
            'stroke-width': '2',
            'stroke-linecap': 'round',
            'stroke-linejoin': 'round',
          }, children: [
            .element(tag: 'line', attributes: {'x1': '6', 'y1': '3', 'x2': '6', 'y2': '15'}, children: []),
            .element(tag: 'circle', attributes: {'cx': '18', 'cy': '6', 'r': '3'}, children: []),
            .element(tag: 'circle', attributes: {'cx': '6', 'cy': '18', 'r': '3'}, children: []),
            .element(tag: 'path', attributes: {'d': 'M18 9a9 9 0 0 1-9 9'}, children: []),
          ]),
        ]),
        h1(classes: 'title', [.text('Triage Verifier')]),
        p(classes: 'subtitle', [.text('Check if a GitHub issue has been LLM-assisted triaged in mboetger/flutter or mboetger/packages')]),
      ]),
      form(
        classes: 'form-group',
        events: {
          'submit': (web.Event event) {
            event.preventDefault();
            if (!isLoading && issueId.trim().isNotEmpty) {
              checkIssue();
            }
          }
        },
        [
          div(classes: 'input-wrapper', [
            input<String>(
              type: .text,
              value: issueId,
              onInput: (val) {
                setState(() => issueId = val);
              },
              classes: 'issue-input',
              attributes: {'placeholder': 'Enter GitHub Issue ID (e.g. 12345)'},
            ),
          ]),
          button(
            type: .submit,
            disabled: isLoading || issueId.trim().isEmpty,
            classes: 'check-button',
            [
              .text(isLoading ? 'Verifying...' : 'Verify Triage Status'),
            ],
          ),
        ],
      ),
      if (isLoading)
        div(classes: 'loading-container', [
          div(classes: 'spinner', []),
          p(classes: 'loading-text', [.text('Searching repository branches...')]),
        ])
      else if (status == 'Found')
        div(classes: 'result-container', [
          for (final branch in matchingBranches)
            div(classes: 'result-card result-success', [
              div(classes: 'result-icon', [
                .element(tag: 'svg', attributes: {
                  'xmlns': 'http://www.w3.org/2000/svg',
                  'viewBox': '0 0 24 24',
                  'fill': 'none',
                  'stroke': 'currentColor',
                  'stroke-width': '2',
                  'stroke-linecap': 'round',
                  'stroke-linejoin': 'round',
                }, children: [
                  .element(tag: 'polyline', attributes: {'points': '20 6 9 17 4 12'}, children: []),
                ]),
              ]),
              div(classes: 'result-content', [
                h3(classes: 'result-title', [.text(branch.name)]),
                p(classes: 'result-desc', [
                  .text('Branch found in ${branch.repository}! Click below to view the commit comparison.')
                ]),
                a(
                  href: branch.compareUrl,
                  classes: 'link-button',
                  attributes: {'target': '_blank'},
                  [
                    .text('View Branch Commits ↗'),
                  ],
                ),
              ]),
            ]),
        ])
      else if (status == 'RateLimited')
        div(classes: 'result-container', [
          div(classes: 'result-card result-error', [
            div(classes: 'result-icon', [
              .element(tag: 'svg', attributes: {
                'xmlns': 'http://www.w3.org/2000/svg',
                'viewBox': '0 0 24 24',
                'fill': 'none',
                'stroke': 'currentColor',
                'stroke-width': '2',
                'stroke-linecap': 'round',
                'stroke-linejoin': 'round',
              }, children: [
                .element(tag: 'circle', attributes: {'cx': '12', 'cy': '12', 'r': '10'}, children: []),
                .element(tag: 'line', attributes: {'x1': '12', 'y1': '8', 'x2': '12', 'y2': '12'}, children: []),
                .element(tag: 'line', attributes: {'x1': '12', 'y1': '16', 'x2': '12.01', 'y2': '16'}, children: []),
              ]),
            ]),
            div(classes: 'result-content', [
              h3(classes: 'result-title', [.text('Rate Limit Exceeded')]),
              p(classes: 'result-desc', [.text('You have exceeded GitHub\'s API rate limit (60 requests/hour per IP). Please wait a while before trying again.')]),
            ]),
          ]),
        ])
      else if (status == 'Not triaged')
        div(classes: 'result-container', [
          div(classes: 'result-card result-error', [
            div(classes: 'result-icon', [
              .element(tag: 'svg', attributes: {
                'xmlns': 'http://www.w3.org/2000/svg',
                'viewBox': '0 0 24 24',
                'fill': 'none',
                'stroke': 'currentColor',
                'stroke-width': '2',
                'stroke-linecap': 'round',
                'stroke-linejoin': 'round',
              }, children: [
                .element(tag: 'circle', attributes: {'cx': '12', 'cy': '12', 'r': '10'}, children: []),
                .element(tag: 'line', attributes: {'x1': '12', 'y1': '8', 'x2': '12', 'y2': '12'}, children: []),
                .element(tag: 'line', attributes: {'x1': '12', 'y1': '16', 'x2': '12.01', 'y2': '16'}, children: []),
              ]),
            ]),
            div(classes: 'result-content', [
              h3(classes: 'result-title', [.text('Not triaged')]),
              p(classes: 'result-desc', [.text('No branch starting with "triage-issue-$searchedIssueId" was found in mboetger/flutter or mboetger/packages.')]),
            ]),
          ]),
        ])
      else
        .empty(),
      if (last20Issues.isNotEmpty)
        div(classes: 'recent-issues-container', [
          h3(classes: 'recent-issues-title', [.text('Recently Triaged Issues')]),
          if (totalTriageIssues != null)
            div(classes: 'badge recent-badge', [.text('$totalTriageIssues total issues triaged')]),
          div(classes: 'recent-issues-list', [
            for (final id in last20Issues)
              a(
                href: '?issue=$id',
                classes: 'recent-issue-chip',
                events: {
                  'click': (web.Event event) {
                    event.preventDefault();
                    web.window.history.pushState(null, '', '?issue=$id');
                    setState(() => issueId = id);
                    checkIssue();
                  }
                },
                [
                  .text('#$id'),
                ],
              ),
          ]),
        ]),
    ]);
  }
}
