"""
Test _normalize_answer function directly
"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.routes.learning import _normalize_answer

def run_tests():
    print("Running tests for _normalize_answer...")
    
    # Test cases: (input_answer, question_type, expected_output)
    test_cases = [
        # Normal inputs
        ("Hello ", "translate", "hello"),
        ("Apple, An", "fill_blank", "apple an"),
        ("True", "true_false", "true"),
        ("đúng", "true_false", "true"),
        ("Sai", "true_false", "false"),
        (None, "multiple_choice", ""),
        
        # Matching inputs: sorted order vs unsorted order
        ("father:Male parent, mother:Female parent", "matching", "father:male parent, mother:female parent"),
        ("mother:Female parent, father:Male parent", "matching", "father:male parent, mother:female parent"),
        ("he:Singular, they:Plural", "matching", "he:singular, they:plural"),
        ("they:Plural, he:Singular", "matching", "he:singular, they:plural"),
        
        # Categorization (which maps to matching)
        ("bedroom:bed, kitchen:fridge", "categorization", "bedroom:bed, kitchen:fridge"),
        ("kitchen:fridge, bedroom:bed", "categorization", "bedroom:bed, kitchen:fridge"),
    ]
    
    failed = 0
    for idx, (ans, q_type, expected) in enumerate(test_cases):
        result = _normalize_answer(ans, q_type)
        if result != expected:
            print(f"FAIL [Case {idx+1}]: input={repr(ans)}, type={repr(q_type)}")
            print(f"       Expected: {repr(expected)}")
            print(f"       Got:      {repr(result)}")
            failed += 1
        else:
            print(f"PASS [Case {idx+1}]: input={repr(ans)} -> {repr(result)}")
            
    if failed == 0:
        print("\nAll normalize_answer tests passed successfully! 🎉")
        sys.exit(0)
    else:
        print(f"\n{failed} tests failed.")
        sys.exit(1)

if __name__ == "__main__":
    run_tests()
