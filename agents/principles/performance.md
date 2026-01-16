---
name: performance-principles
domain: performance
description: Critique principles for high-performance code
---

# Performance Principles

Code MUST adhere to these performance requirements:

## Database & Queries

1. **No N+1 Queries** - Batch database calls. Use eager loading, joins, or subqueries instead of loops.

2. **Proper Indexing** - Ensure queries use appropriate indexes. Avoid full table scans on large tables.

3. **Query Optimization** - Use EXPLAIN ANALYZE to verify query plans. Avoid SELECT *.

## Caching & Memory

4. **Strategic Caching** - Cache repeated computations and frequently accessed data. Set appropriate TTLs.

5. **Memory Efficiency** - No memory leaks. Use bounded allocations. Release resources promptly.

6. **Lazy Loading** - Load data only when needed. Defer expensive operations until required.

## I/O & Concurrency

7. **Async I/O** - Use non-blocking operations for network, file, and database access where possible.

8. **Connection Pooling** - Reuse database and HTTP connections. Configure pool sizes appropriately.

9. **Parallel Processing** - Use concurrent execution for independent operations. Avoid sequential bottlenecks.

## Algorithm & Code

10. **Algorithmic Efficiency** - Choose appropriate data structures. Avoid O(n^2) or worse when O(n) is possible.

11. **Minimize Allocations** - Reduce object creation in hot paths. Reuse buffers and objects.

12. **Early Exit** - Return early when conditions are met. Avoid unnecessary computation.

## Checklist

When reviewing code, verify:
- [ ] No N+1 query patterns
- [ ] Database queries use indexes
- [ ] Appropriate caching in place
- [ ] No memory leaks
- [ ] Async operations for I/O
- [ ] Connection pooling configured
- [ ] Efficient algorithms used
- [ ] No unnecessary loops or iterations
- [ ] Resources properly released
- [ ] Pagination for large result sets
