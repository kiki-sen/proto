using Microsoft.AspNetCore.Mvc;

namespace BookRecommenderApi.Controllers
{
    [ApiController]
    [Route("[controller]")]
    public class GreetingController : ControllerBase
    {
        [HttpPost]
        public IActionResult Post([FromBody] GreetingRequest request)
        {
            var message = $"Hello, {request.Name}!";
            return Ok(new { message });
        }
    }

    public class GreetingRequest
    {
        public string Name { get; set; }
    }

}
