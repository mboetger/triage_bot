import * as admin from 'firebase-admin';
import { onRequest } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { defineSecret } from 'firebase-functions/params';
import axios from 'axios';

const githubToken = defineSecret('GITHUB_TOKEN');

admin.initializeApp();
const db = admin.firestore();

export const calculateDailyBranchStatistics = onSchedule(
  {
    schedule: 'every 15 minutes',
    secrets: [githubToken],
  },
  async (event) => {
    try {
      const token = githubToken.value();
      const config: any = {
        headers: {
          'Connection': 'close'
        }
      };
      if (token) {
        config.headers['Authorization'] = `Bearer ${token}`;
      }

      // 1. Fetch all triage branches from GitHub
      const url = 'https://api.github.com/repos/mboetger/flutter/git/matching-refs/heads/triage-issue-';
      const response = await axios.get(url, config);
      const data = response.data;
      
      const githubBranches = new Set<string>();
      for (const item of data) {
        const ref = item.ref as string;
        if (ref && ref.startsWith('refs/heads/')) {
          githubBranches.add(ref.substring('refs/heads/'.length));
        }
      }

      // 2. Fetch all existing branch stats from Firestore to find stale/deleted ones
      const branchStatsSnap = await db.collection('branch_stats').get();
      const firestoreBranches = new Map<string, FirebaseFirestore.Timestamp>();
      
      let branchesDeleted = 0;
      const batch = db.batch();

      for (const doc of branchStatsSnap.docs) {
        const branchName = doc.id;
        const lastCalculated = doc.get('lastCalculated');
        
        if (!githubBranches.has(branchName)) {
          // Branch no longer exists on GitHub, delete it
          batch.delete(doc.ref);
          branchesDeleted++;
        } else {
          firestoreBranches.set(branchName, lastCalculated);
        }
      }

      if (branchesDeleted > 0) {
        await batch.commit();
        console.log(`Deleted ${branchesDeleted} old branches from Firestore.`);
      }

      // 3. Find branches that need to be calculated (new or older than 24 hours)
      const now = Date.now();
      const ONE_DAY_MS = 24 * 60 * 60 * 1000;
      
      const toCalculate: string[] = [];
      for (const branchName of githubBranches) {
        const lastCalculated = firestoreBranches.get(branchName);
        if (!lastCalculated || (now - lastCalculated.toMillis() > ONE_DAY_MS)) {
          toCalculate.push(branchName);
        }
      }

      if (toCalculate.length === 0 && branchesDeleted === 0) {
        console.log('No branches to update or delete. Exiting.');
        return;
      }

      // 4. Process up to 10 branches
      const branchesToProcess = toCalculate.slice(0, 10);
      let branchesUpdated = 0;

      for (const branchName of branchesToProcess) {
        try {
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
            const branchFiles: Record<string, { changes: number }> = {};
            
            if (files && Array.isArray(files)) {
              for (const file of files) {
                const filename = file.filename;
                if (filename.includes('/test/') || filename.startsWith('test/') || filename.endsWith('_test.dart')) {
                  continue;
                }
                branchFiles[filename] = { changes: file.changes };
              }
            }
            
            await db.collection('branch_stats').doc(branchName).set({
              lastCalculated: admin.firestore.FieldValue.serverTimestamp(),
              files: branchFiles
            });
            branchesUpdated++;
          }
        } catch (e) {
          console.error(`Error processing branch ${branchName}:`, e);
        }
        
        await new Promise(resolve => setTimeout(resolve, 500));
      }

      // 5. Aggregate all stats if anything changed
      if (branchesUpdated > 0 || branchesDeleted > 0) {
        console.log(`Aggregating stats (${branchesUpdated} updated, ${branchesDeleted} deleted)...`);
        
        const allStatsSnap = await db.collection('branch_stats').get();
        const globalFileStats: Record<string, { changes: number, branches: number, branchNames: string[] }> = {};
        
        for (const doc of allStatsSnap.docs) {
          const branchName = doc.id;
          const files = doc.get('files') || {};
          for (const [filename, fileData] of Object.entries<any>(files)) {
            if (!globalFileStats[filename]) {
              globalFileStats[filename] = { changes: 0, branches: 0, branchNames: [] };
            }
            globalFileStats[filename].changes += fileData.changes || 0;
            globalFileStats[filename].branches += 1;
            globalFileStats[filename].branchNames.push(branchName);
          }
        }

        const sortedFiles = Object.entries(globalFileStats)
          .sort((a, b) => b[1].branches - a[1].branches)
          .slice(0, 50);

        await db.collection('statistics').doc('daily').set({
          lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
          totalBranchesAnalyzed: allStatsSnap.size,
          topFiles: sortedFiles.map(([filename, stats]) => ({
            filename,
            changes: stats.changes,
            branches: stats.branches,
            branchNames: stats.branchNames
          }))
        });
        
        console.log('Global statistics aggregated and saved.');
      }

    } catch (error) {
      console.error('Error in calculateDailyBranchStatistics:', error);
    }
  }
);

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
