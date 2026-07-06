import * as admin from 'firebase-admin';
import { onRequest } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { defineSecret } from 'firebase-functions/params';
import axios from 'axios';

const githubToken = defineSecret('GITHUB_TOKEN');

admin.initializeApp();

const db = admin.firestore();

// Fetch daily branch statistics
export const calculateDailyBranchStatistics = onSchedule(
  {
    schedule: 'every 12 hours',
    secrets: [githubToken],
  },
  async (event) => {
    try {
      const token = githubToken.value();
      const config = token ? { headers: { Authorization: `Bearer ${token}` } } : {};

      const url = 'https://api.github.com/repos/mboetger/flutter/git/matching-refs/heads/triage-issue-';
      const response = await axios.get(url, config);
    const data = response.data;
    
    const fileStats: Record<string, { changes: number, branches: number }> = {};
    let totalBranchesAnalyzed = 0;

    for (const item of data) {
      const ref = item.ref as string;
      if (ref && ref.startsWith('refs/heads/')) {
        const branchName = ref.substring('refs/heads/'.length);
        
        try {
          // Compare with base master
          let baseSha = '';
          const compareUrl = `https://api.github.com/repos/flutter/flutter/compare/master...mboetger:${branchName}`;
          try {
            const compareRes = await axios.get(compareUrl, config);
            baseSha = compareRes.data.merge_base_commit.sha;
          } catch (e) {
            const compareUrlFallback = `https://api.github.com/repos/mboetger/flutter/compare/flutter:master...${branchName}`;
            const compareResFallback = await axios.get(compareUrlFallback, config);
            baseSha = compareResFallback.data.merge_base_commit.sha;
          }

          if (baseSha) {
            const finalCompareUrl = `https://api.github.com/repos/mboetger/flutter/compare/${baseSha}...${branchName}`;
            const diffRes = await axios.get(finalCompareUrl, config);
            
            const files = diffRes.data.files;
            if (files && Array.isArray(files)) {
              for (const file of files) {
                const filename = file.filename;
                
                if (filename.includes('/test/') || filename.startsWith('test/') || filename.endsWith('_test.dart')) {
                  continue;
                }

                const changes = file.changes;
                
                if (!fileStats[filename]) {
                  fileStats[filename] = { changes: 0, branches: 0 };
                }
                fileStats[filename]!.changes += changes;
                fileStats[filename]!.branches += 1;
              }
            }
            totalBranchesAnalyzed++;
          }
        } catch (e) {
          console.error(`Error processing branch ${branchName}:`, e);
        }
      }
    }

    const sortedFiles = Object.entries(fileStats)
      .sort((a, b) => b[1].branches - a[1].branches)
      .slice(0, 50); // top 50 files

    await db.collection('statistics').doc('daily').set({
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      totalBranchesAnalyzed,
      topFiles: sortedFiles.map(([filename, stats]) => ({
        filename,
        changes: stats.changes,
        branches: stats.branches
      }))
    });
    
    console.log('Daily statistics calculated and saved.');

  } catch (error) {
    console.error('Error calculating statistics:', error);
  }
});

export const getBranchStatistics = onRequest({ cors: true }, async (req, res) => {
  try {
    const doc = await db.collection('statistics').doc('daily').get();
    if (!doc.exists) {
      res.status(404).json({ error: 'Statistics not found' });
      return;
    }
    res.json(doc.data());
  } catch (error) {
    console.error('Error fetching statistics:', error);
    res.status(500).json({ error: 'Internal Server Error' });
  }
});
