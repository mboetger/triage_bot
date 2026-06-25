import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

class BranchInfo {
  BranchInfo(this.name, this.compareUrl);
  final String name;
  final String compareUrl;
}

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
      // Use GitHub Git matching-refs API to find all branches matching triage-issue-<ISSUE_ID>*
      final url = Uri.parse('https://api.github.com/repos/mboetger/flutter/git/matching-refs/heads/triage-issue-$cleanId');
      final response = await http.get(url);

      // Check if GitHub's IP-based rate limit has been exceeded (403/429)
      if (response.statusCode == 403 || response.statusCode == 429) {
        setState(() {
          isLoading = false;
          status = 'RateLimited';
          matchingBranches = [];
        });
        return;
      }

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final branchInfos = <BranchInfo>[];

        for (final item in data) {
          final ref = item['ref'] as String?;
          if (ref != null && ref.startsWith('refs/heads/')) {
            final branchName = ref.substring('refs/heads/'.length);

            // Fetch the merge base commit SHA against upstream flutter/flutter:master
            // because mboetger/flutter:master may be thousands of commits behind upstream.
            String baseSha = '';
            try {
              final compareUrl = Uri.parse('https://api.github.com/repos/flutter/flutter/compare/master...mboetger:$branchName');
              final compareRes = await http.get(compareUrl);
              if (compareRes.statusCode == 200) {
                final compareData = jsonDecode(compareRes.body);
                baseSha = compareData['merge_base_commit']['sha'] as String;
              } else {
                final compareUrlFallback = Uri.parse('https://api.github.com/repos/mboetger/flutter/compare/flutter:master...$branchName');
                final compareResFallback = await http.get(compareUrlFallback);
                if (compareResFallback.statusCode == 200) {
                  final compareDataFallback = jsonDecode(compareResFallback.body);
                  baseSha = compareDataFallback['merge_base_commit']['sha'] as String;
                }
              }
            } catch (_) {}

            final finalCompareUrl = baseSha.isNotEmpty
                ? 'https://github.com/mboetger/flutter/compare/$baseSha...$branchName'
                : 'https://github.com/mboetger/flutter/compare/$branchName';

            branchInfos.add(BranchInfo(branchName, finalCompareUrl));
          }
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
        p(classes: 'subtitle', [.text('Check if a GitHub issue has been triaged in mboetger/flutter')]),
      ]),
      div(classes: 'form-group', [
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
          disabled: isLoading || issueId.trim().isEmpty,
          onClick: (isLoading || issueId.trim().isEmpty) ? null : checkIssue,
          classes: 'check-button',
          [
            .text(isLoading ? 'Verifying...' : 'Verify Triage Status'),
          ],
        ),
      ]),
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
                  .text('Branch found! Click below to view the commit comparison.')
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
              p(classes: 'result-desc', [.text('No branch starting with "triage-issue-$searchedIssueId" was found in mboetger/flutter.')]),
            ]),
          ]),
        ])
      else
        .empty(),
    ]);
  }
}
