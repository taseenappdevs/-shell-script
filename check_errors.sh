#!/bin/bash

set -e

echo "🚀 Starting Flutter Error Check Script"
echo "-------------------------------------"

echo "🔧 Step 1: Generating code (build_runner)..."
flutter pub run build_runner build --delete-conflicting-outputs
echo "✅ Code generation complete."

echo "🔍 Step 2: Running flutter analyze..."
flutter analyze > analysis.log || true

if grep -q "error •" analysis.log; then
  echo "❌ Static analysis found errors:"
  grep "error •" analysis.log
  rm analysis.log
  exit 1
else
  echo "✅ No static analysis errors found."
fi

rm analysis.log

echo "🧪 Step 3: Running flutter test..."
flutter test || {
  echo "❌ One or more tests failed."
  exit 1
}

echo "✅ All tests passed successfully."
echo "🎉 All checks completed without errors!"
